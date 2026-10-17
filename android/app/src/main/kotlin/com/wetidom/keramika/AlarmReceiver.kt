package com.wetidom.keramika

import android.app.ActivityOptions
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.Calendar

class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP, "keramika:alarm")
        wakeLock.acquire(300_000)  // 5 минут — хватает для разблокировки и решения задачи

        try {
            val id = intent.getIntExtra("alarm_id", 0)
            val title = intent.getStringExtra("title") ?: "Alarm"
            val body = intent.getStringExtra("body") ?: ""
            val channelName = intent.getStringExtra("channel_name") ?: "Будильники"
            val soundName = normalizeSoundName(intent.getStringExtra("sound_name"))
            val vibrate = intent.getBooleanExtra("vibrate", true)
            val payload = intent.getStringExtra("payload") ?: ""
            val fullscreen = intent.getBooleanExtra("fullscreen", true)
            val hour = intent.getIntExtra("hour", 0)
            val minute = intent.getIntExtra("minute", 0)
            val repeatDays = intent.getStringExtra("repeat_days") ?: ""
            val customPath = intent.getStringExtra("custom_sound_path")

            Log.d(TAG, "Alarm id=$id sound=$soundName vibrate=$vibrate")
            // Постоянный лог срабатываний (внешний файл — читается через adb
            // без root: /sdcard/Android/data/com.wetidom.keramika/files/).
            // Нужен, чтобы понять, почему будильник «не сработал» — реально
            // ли приёмник не запустился или уведомление не показалось.
            // «missed» = догон пропущенного срабатывания после перезагрузки
            // (телефон был выключен к моменту будильника).
            val isMissed = intent.action == ACTION_MISSED
            logToFile(
                context,
                "ALARM FIRED id=$id title=$title sound=$soundName custom=${customPath ?: "-"} missed=$isMissed",
            )

            // Пропущенное срабатывание подписываем явно: без этого человек
            // думает, что будильник просто поставлен на завтра.
            val shownTitle = if (isMissed) "Проспал · $title" else title
            val shownBody = if (isMissed) {
                "Было на ${"%02d:%02d".format(hour, minute)}, телефон не работал"
            } else {
                body
            }

            val isRealityCheck = payload == "rc"

            if (vibrate) doVibrate(context)

            // Право полноэкранного показа читаем ОДИН раз, до сборки
            // уведомления, и отдаём его в билдер (см. showNotification).
            val fsGranted = fullScreenAllowed(context)
            logToFile(
                context,
                "FSI CHECK granted=$fsGranted interactive=${isInteractive(context)} " +
                    "locked=${isKeyguardLocked(context)}",
            )

            // ЕДИНСТВЕННЫЙ источник звука будильника.
            //
            // Раньше звук шёл откуда угодно: из сигнала канала уведомления,
            // из MediaPlayer сервиса и ещё из Flutter-плеера на экране задачи.
            // Канал в Android НЕ меняет звук после создания, поэтому первым
            // же срабатыванием (часто — проверкой реальности, у которой
            // системный звук уведомлений) звук «застывал» навсегда, и
            // будильник звенел чужим. Теперь канал будильника ТИХИЙ, а
            // звонок крутит foreground-сервис выбранным файлом. Он не зависит
            // ни от права full-screen intent, ни от настроек канала.
            // Проверки реальности (payload == "rc") не звенят — у них тихий
            // пуш со звуком своего канала.
            var ringStarted = false
            if (!isRealityCheck) {
                ringStarted = AlarmForegroundService.start(
                    ctx = context,
                    soundName = soundName,
                    customPath = customPath,
                    vibrate = vibrate,
                    title = shownTitle,
                    body = shownBody,
                    payload = payload,
                )
                logToFile(context, "RING START id=$id started=$ringStarted")
            }

            showNotification(
                context, id, shownTitle, shownBody, channelName, soundName,
                vibrate, payload, fullscreen && fsGranted, customPath,
                isRealityCheck,
                // Сервис — основной звонок. Если система отказала ему в
                // старте (ограничения фоновых сервисов Android 12+), звук
                // должен остаться хотя бы в самом уведомлении — тишина
                // вместо будильника недопустима. Тогда идём на отдельный
                // канал под конкретный звук (см. createChannel).
                fallbackSound = !isRealityCheck && !ringStarted,
            )

            // Стартуем Activity ТОЛЬКО для payload-будильников (не rc).
            // FIX (другой путь на экран): всегда вызываем, а не только
            // при включённом полноэкранном режиме. Тумблер теперь влияет
            // только на showWhenLocked/turnScreenOn (через extra
            // fullscreen_intent), а не на сам факт вывода на экран.
            // Без FSI-права (API 34+) ActivityOptions.backgroundStart
            // даёт запасной путь через PendingIntent.
            if (!isRealityCheck) {
                launchAlarmActivity(context, id, payload, fullscreen)
            }

            // Перепланируем следующий — но НЕ для догона: BootReceiver уже
            // взвёл ближайший будущий срабатывание, второй раз означал бы
            // задвоение будильника.
            if (repeatDays.isNotEmpty() && !isMissed) {
                rescheduleNext(context, id, intent, hour, minute, repeatDays)
            }
        } catch (e: Exception) {
            // Непойманное исключение отсюда убивает процесс, а вместе с ним и
            // только что стартованный AlarmForegroundService: уведомление
            // остаётся, звук замолкает. Именно так будильник и «не звенел».
            logToFile(
                context,
                "RECEIVER ERROR id=${intent.getIntExtra("alarm_id", 0)} " +
                    "error=${e.javaClass.simpleName}: ${e.message}",
            )
        } finally {
            try { wakeLock.release() } catch (_: Exception) {}
        }
    }

    /**
     * Приводит имя звука к имени ресурса в res/raw.
     *
     * Важно: Dart присылает уже «приземлённые» имена (`gentle`), а плагин
     * планировщика мапит человеческие (`Gentle`). Принимаем оба написания —
     * иначе `else -> raw` молча проглатывал расхождение и уведомление
     * собиралось с URI на несуществующий ресурс.
     */
    private fun normalizeSoundName(raw: String?): String {
        return when (raw) {
            "Default", "default", "alarm_default" -> "alarm_default"
            "Gentle", "gentle" -> "gentle"
            "Classic", "classic" -> "classic"
            "Digital", "digital" -> "digital"
            "Nature", "nature" -> "nature"
            // Свой файл: имя ресурса не нужно, путь лежит в отдельном extra.
            // alarm_default остаётся только страховкой на случай, если путь
            // не доехал (тогда всё равно прозвенит встроенный звонок).
            "Custom", "custom" -> "alarm_default"
            "System", "system", "system_default" -> "system_default"
            else -> raw ?: "alarm_default"
        }
    }

    // ── Полноэкранный запуск ──────────────────────────────

    /**
     * Открывает экран будильника поверх блокировки.
     *
     * Почему не `context.startActivity`: с Android 10 система блокирует
     * запуск Activity из фона, и приёмник остаётся только с уведомлением
     * в шторке — ровно то, на что жаловался пользователь («будильник не
     * срабатывает полноэкранно»). Полагаться на один full-screen intent
     * тоже нельзя: на Android 14+ app-op `USE_FULL_SCREEN_INTENT` по
     * умолчанию в `ignore`, а система (и MIUI/HyperOS) умеет снимать его
     * сама после обновления или перезагрузки — это и есть «разрешение
     * спадает».
     *
     * Выход: задокументированное исключение для будильников и звонков —
     * `ActivityOptions`, которые явно РАЗРЕШАЮТ фоновый старт Activity по
     * PendingIntent (API 34+). Оно не требует никакого системного права и
     * не может быть отозвано. FSI при этом остаётся как улучшение (когда
     * право выдано), но больше не является единственным путём наверх.
     */
    private fun launchAlarmActivity(ctx: Context, id: Int, payload: String, showWhenLocked: Boolean) {
        val i = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_NO_ANIMATION
            putExtra("payload", payload)
            // MainActivity по этому флагу включает showWhenLocked /
            // turnScreenOn / keepScreenOn и просит снять ключгейрд.
            putExtra("alarm_launch", true)
            // FIX: «поверх блокировки» теперь управляется ОТДЕЛЬНО от факта
            // вывода на экран. Активность всё равно открывается (заносит
            // пользователя на экран задачи), но showWhenLocked/keyguard
            // применяются только если тумблер включён.
            putExtra("alarm_fullscreen", showWhenLocked)
        }
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        // Опция «разрешить фоновый старт» принадлежит ОТПРАВИТЕЛЮ PendingIntent,
        // поэтому она уезжает в pi.send(), а не в getActivity(). На created-стороне
        // оставляем только creator-режим: pendingIntentBackgroundActivityStartMode
        // внутри бандла создания Android 15 (targetSdk 36) отвергает
        // IllegalArgumentException — а он вылетал из onReceive, убивал процесс
        // вместе с недавно стартованным AlarmForegroundService, и будильник
        // молчал: уведомление было, звука не было.
        val creatorOptions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ActivityOptions.makeBasic().apply {
                pendingIntentCreatorBackgroundActivityStartMode =
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
            }.toBundle()
        } else {
            null
        }

        val pi = try {
            if (creatorOptions != null) {
                PendingIntent.getActivity(ctx, id, i, piFlags, creatorOptions)
            } else {
                PendingIntent.getActivity(ctx, id, i, piFlags)
            }
        } catch (e: Exception) {
            logToFile(
                ctx,
                "ACTIVITY PI OPT FAILED id=$id error=${e.javaClass.simpleName} → plain",
            )
            // Без опций PendingIntent всё равно создаётся и отправляется:
            // отказ от опции не должен лишать будильник экрана задачи.
            try {
                PendingIntent.getActivity(ctx, id, i, piFlags)
            } catch (e2: Exception) {
                logToFile(ctx, "ACTIVITY PI FAILED id=$id error=${e2.javaClass.simpleName}")
                return
            }
        }

        val senderOptions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ActivityOptions.makeBasic().apply {
                pendingIntentBackgroundActivityStartMode =
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
            }.toBundle()
        } else {
            null
        }

        try {
            // Перегрузка send(..., Bundle options) появилась только в API 34,
            // поэтому ниже 34 отправляем обычным send(context, 0, null).
            if (senderOptions != null) {
                pi.send(ctx, 0, null, null, null, null, senderOptions)
            } else {
                pi.send(ctx, 0, null)
            }
            logToFile(ctx, "ACTIVITY START OK id=$id via=pendingIntent")
        } catch (e: Exception) {
            // Ожидаемо на старых Android: ordinary start из фона режется
            // системой. Оставляем как запасной путь — на API < 34 он часто
            // срабатывает, если приложение недавно было на экране.
            logToFile(
                ctx,
                "ACTIVITY START BLOCKED id=$id error=${e.javaClass.simpleName}: ${e.message}",
            )
            try {
                ctx.startActivity(i)
                logToFile(ctx, "ACTIVITY START OK id=$id via=direct")
            } catch (e2: Exception) {
                logToFile(
                    ctx,
                    "ACTIVITY START BLOCKED id=$id direct error=${e2.javaClass.simpleName}",
                )
            }
        }
    }

    // ── Вибрация ──────────────────────────────────────────

    @Suppress("DEPRECATION")
    private fun doVibrate(ctx: Context) {
        try {
            val p = longArrayOf(0, 800, 400, 800, 400, 800)
            val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                    .defaultVibrator
            } else {
                ctx.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            // HyperOS глушит вибрацию без назначения (usage UNKNOWN стоит в
            // «Сила вибрации → Другое = OFF»). Просим USAGE_ALARM явно —
            // иначе будильник беззвучно дрожит лишь на бумаге.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                vib.vibrate(
                    VibrationEffect.createWaveform(p, 0),
                    android.os.VibrationAttributes.Builder()
                        .setUsage(android.os.VibrationAttributes.USAGE_ALARM)
                        .build(),
                )
            } else {
                vib.vibrate(VibrationEffect.createWaveform(p, 0))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Vibrate failed: $e")
        }
    }

    // ── Уведомление ───────────────────────────────────────

    private fun showNotification(
        ctx: Context, id: Int, title: String, body: String,
        channelName: String, soundName: String,
        vibrate: Boolean, payload: String,
        // «Показывать во весь экран»: уже содержит и намерение пользователя,
        // и реальное системное право (см. onReceive).
        useFullScreen: Boolean,
        customPath: String?,
        isRealityCheck: Boolean,
        fallbackSound: Boolean = false,
    ) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Каналы РАЗДЕЛЬНЫЕ и навсегда.
        //
        // Раньше и будильники, и проверки реальности писали в один
        // `keramika_alarm_v2`. Звук канала в Android нельзя изменить после
        // создания: кто создал канал первым, тот и задал звук навсегда.
        // Проверка реальности создавала его с системным звуком уведомлений —
        // отсюда «будильник звенит каким-то другим звуком».
        //
        // Запасной канал — отдельный на КАЖДЫЙ звук: так запасной звонок
        // всегда совпадает с выбранным, а не с тем, что случайно «заморозил»
        // общий канал.
        val channelId = when {
            isRealityCheck -> RC_CHANNEL
            fallbackSound -> fallbackChannelId(soundName, customPath)
            else -> ALARM_CHANNEL
        }
        createChannel(ctx, nm, channelId, channelName, soundName, customPath, vibrate, isRealityCheck, fallbackSound)

        // Intent для fullScreenIntent и contentIntent — ОДИН на двоих.
        // CLEAR_TOP сознательно УБРАН: он пересоздавал всю задачу
        // приложения и стирал только что открытый экран будильника.
        val tapIntent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_NO_ANIMATION
            putExtra("payload", payload)
            putExtra("alarm_launch", !isRealityCheck)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_UPDATE_CURRENT
        val pi = PendingIntent.getActivity(ctx, id, tapIntent, flags)

        // Intent для удаления уведомления — предотвращает случайное свайп-закрытие
        val cancelIntent = Intent(ctx, MainActivity::class.java).apply {
            action = "com.wetidom.keramika.CANCEL_ALARM"
            putExtra("alarm_id", id)
        }
        val cancelFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
        val cancelPi = PendingIntent.getActivity(ctx, id + 1000, cancelIntent, cancelFlags)

        // Билдер: звук НЕ задаём — его играет AlarmForegroundService.
        // Иначе получалось два-три разных звонка одновременно, а звук канала
        // к тому же был «заморожен» первым срабатыванием.
        // Исключение — запасной путь, когда сервис звонка не стартовал:
        // тогда звук живёт в самом уведомлении (канал под него уже готов).
        val builder = NotificationCompat.Builder(ctx, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(false)
            .setOngoing(true)
            .setContentIntent(pi)
            .setColor(0xFFFDF2F6.toInt())
            .setDeleteIntent(cancelPi)  // Защита от случайного закрытия

        if (fallbackSound) {
            resolveSoundUri(ctx, soundName, customPath)?.let { builder.setSound(it) }
        }

        if (vibrate) {
            builder.setVibrate(longArrayOf(0, 800, 400, 800, 400, 800))
            builder.setDefaults(NotificationCompat.DEFAULT_VIBRATE)
        }

        // Full-screen intent — ТОЛЬКО когда он реально разрешён. Постить
        // заведомо отклоняемые full-screen-показы бессмысленно: система
        // записывает каждый как отказ вокруг права, а само право теперь не
        // является единственным способом открыть экран (см.
        // launchAlarmActivity).
        if (useFullScreen) builder.setFullScreenIntent(pi, true)

        try {
            NotificationManagerCompat.from(ctx).notify(id, builder.build())
            Log.d(TAG, "Notification id=$id channel=$channelId fsi=$useFullScreen")
            logToFile(
                ctx,
                "NOTIFICATION POSTED id=$id channel=$channelId fsi=$useFullScreen",
            )
        } catch (e: SecurityException) {
            Log.e(TAG, "Notification failed: $e")
            logToFile(ctx, "NOTIFICATION FAILED id=$id error=$e")
        }
    }

    /**
     * Создаёт (или молча переиспользует) канал уведомления.
     *
     * Звук и вибрация канала НЕ меняются после первого создания — поэтому
     * канал будильника делаем ТИХИМ: звучит только сервис, выбранным
     * пользователем файлом. Канал проверок реальности, наоборот, хранит
     * системный звук уведомлений (сервис для них не запускается).
     *
     * Старые каналы со звуком удаляем один раз: иначе Android продолжал бы
     * держать «замороженный» чужой звук, а пользователь — видеть в настройках
     * канал, который мы уже не используем.
     */
    private fun createChannel(
        ctx: Context,
        nm: NotificationManager,
        channelId: String,
        channelName: String,
        soundName: String,
        customPath: String?,
        vibrate: Boolean,
        isRealityCheck: Boolean,
        fallbackSound: Boolean,
    ) {
        // Замороженные каналы прошлых версий: звук в них уже не поправить,
        // только удалить. Удаление канала безопасно — уведомления просто
        // уходят в новый канал при следующем срабатывании.
        if (!channelsCleanedUp) {
            channelsCleanedUp = true
            // keramika_alarm_ring НЕ трогаем — это канал самого сервиса
            // звонка, удалить его значит снять foreground-уведомление.
            for (stale in listOf("keramika_alarm_v2", "keramika_alarm_v1")) {
                try {
                    if (nm.getNotificationChannel(stale) != null) nm.deleteNotificationChannel(stale)
                } catch (_: Exception) {}
            }
        }

        if (nm.getNotificationChannel(channelId) != null) return

        val channel = if (isRealityCheck) {
            NotificationChannel(channelId, "Проверки реальности", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Напоминания проверок реальности"
                // Системный звук уведомлений: пользователь управляет им
                // в настройках телефона, а не у нас в приложении.
                val uri = android.media.RingtoneManager.getDefaultUri(
                    android.media.RingtoneManager.TYPE_NOTIFICATION
                )
                if (uri != null) {
                    setSound(
                        uri,
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                }
                enableVibration(vibrate)
                enableLights(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                setShowBadge(true)
            }
        } else {
            NotificationChannel(
                channelId,
                channelName.ifBlank { "Будильники" },
                NotificationManager.IMPORTANCE_MAX,
            ).apply {
                description = if (fallbackSound) {
                    "Срабатывания будильников (звук в самом уведомлении)"
                } else {
                    "Срабатывания будильников"
                }
                if (fallbackSound) {
                    // Сервис звонка не поднялся — единственный источник звука
                    // теперь канал, поэтому он создаётся под КОНКРЕТНЫЙ звук
                    // (id канала тоже зависит от звука, см. fallbackChannelId).
                    setSound(
                        resolveSoundUri(ctx, soundName, customPath),
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                } else {
                    // ТИХИЙ канал. Звук крутит AlarmForegroundService
                    // выбранным файлом — он меняется вместе с настройкой
                    // будильника, а звук канала меняться не умеет.
                    setSound(null, null)
                }
                enableVibration(if (fallbackSound) vibrate else false)
                enableLights(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                setBypassDnd(true)
                setShowBadge(true)
            }
        }

        try {
            nm.createNotificationChannel(channel)
        } catch (e: Exception) {
            // Даже если канал не создался, уведомление обязано показаться.
            Log.e(TAG, "Channel $channelId failed: $e")
        }
    }

    /**
     * Отдельный канал на каждый звук — для запасного пути, когда сервис
     * звонка не стартовал. Звук канала нельзя перезаписать, поэтому вместо
     * одного общего канала (который «заморозил» бы первый же звук
     * навсегда) создаётся свой канал под конкретный файл: поменяли звук —
     * создался новый канал, и звучит ровно выбранное.
     */
    private fun fallbackChannelId(soundName: String, customPath: String?): String {
        // String.hashCode() в Java стабилен между запусками (алгоритм
        // зафиксирован), поэтому канал под один и тот же файл получит один
        // и тот же id и после перезагрузки.
        val key = if (!customPath.isNullOrEmpty()) {
            "custom_${Integer.toHexString(customPath.hashCode())}"
        } else {
            soundName
        }
        return "keramika_alarm_fb_$key"
    }

    /**
     * URI выбранного звука: свой файл → системный звук уведомлений →
     * встроенный ресурс res/raw. `null` если ничего не нашлось.
     *
     * [ctx] нужен только для ресурса приложения; для file:// он не требуется,
     * поэтому при создании канала допустимо передавать null (на практике
     * канал создаётся уже с контекстом, но сигнатуру держим простой).
     */
    private fun resolveSoundUri(ctx: Context?, soundName: String, customPath: String?): Uri? {
        return try {
            when {
                !customPath.isNullOrEmpty() -> Uri.parse("file://$customPath")
                soundName == "system_default" ->
                    android.media.RingtoneManager.getDefaultUri(
                        android.media.RingtoneManager.TYPE_NOTIFICATION
                    )
                ctx != null -> Uri.parse("android.resource://${ctx.packageName}/raw/$soundName")
                else -> null
            }
        } catch (e: Exception) {
            Log.e(TAG, "resolveSoundUri failed: $e")
            null
        }
    }

    /**
     * Разрешено ли системе открыть Activity по full-screen intent.
     * `false` = уведомление покажется только «шапкой»; экран будильника
     * при этом всё равно выйдет через launchAlarmActivity.
     *
     * До API 34 такого права нет — full-screen показ доступен всегда.
     */
    private fun fullScreenAllowed(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        return try {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.canUseFullScreenIntent()
        } catch (e: Exception) {
            Log.e(TAG, "canUseFullScreenIntent failed: $e")
            false
        }
    }

    /** Экран включён (в т.ч. залочен)? Только для строки лога. */
    private fun isInteractive(ctx: Context): Boolean {
        return try {
            (ctx.getSystemService(Context.POWER_SERVICE) as PowerManager).isInteractive
        } catch (_: Exception) {
            false
        }
    }

    /** Стоит ли ключгейрд. Только для строки лога. */
    private fun isKeyguardLocked(ctx: Context): Boolean {
        return try {
            val km = ctx.getSystemService(Context.KEYGUARD_SERVICE)
                as android.app.KeyguardManager
            km.isKeyguardLocked
        } catch (_: Exception) {
            false
        }
    }

    // ── Постоянный лог ─────────────────────────────────────

    private fun logToFile(ctx: Context, msg: String) = AlarmLog.write(ctx, msg)

    // ── Повтор ────────────────────────────────────────────

    private fun rescheduleNext(ctx: Context, alarmId: Int, orig: Intent, h: Int, m: Int, daysStr: String) {
        val days = daysStr.split(",").mapNotNull { it.trim().toIntOrNull() }
        if (days.isEmpty()) return

        val now = Calendar.getInstance()
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, h); set(Calendar.MINUTE, m)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        if (!next.after(now) || !days.contains(dow(next))) {
            for (i in 1..14) { next.add(Calendar.DAY_OF_YEAR, 1); if (days.contains(dow(next))) break }
        }

        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(ctx, AlarmReceiver::class.java)
        intent.putExtras(orig.extras ?: return)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_UPDATE_CURRENT
        val pi = PendingIntent.getBroadcast(ctx, alarmId, intent, flags)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                !am.canScheduleExactAlarms()) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.timeInMillis, pi)
                } else {
                    am.set(AlarmManager.RTC_WAKEUP, next.timeInMillis, pi)
                }
            } else {
                am.setAlarmClock(AlarmManager.AlarmClockInfo(next.timeInMillis, pi), pi)
            }
            Log.d(TAG, "Rescheduled id=$alarmId")
            AlarmLog.write(
                ctx,
                "SCHEDULE id=$alarmId api=${if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) "whileIdle" else "alarmClock"} " +
                    "fire=${AlarmLog.time(next.timeInMillis)}",
            )
        } catch (e: Exception) {
            Log.e(TAG, "Could not reschedule id=$alarmId", e)
            AlarmLog.write(ctx, "SCHEDULE FAILED id=$alarmId error=${e.javaClass.simpleName}")
        }
    }

    private fun dow(cal: Calendar): Int = when (cal.get(Calendar.DAY_OF_WEEK)) {
        Calendar.MONDAY -> 1; Calendar.TUESDAY -> 2; Calendar.WEDNESDAY -> 3
        Calendar.THURSDAY -> 4; Calendar.FRIDAY -> 5; Calendar.SATURDAY -> 6
        Calendar.SUNDAY -> 7; else -> 0
    }

    companion object {
        private const val TAG = "AlarmReceiver"

        /** Канал будильников (тихий — звучит сервис). */
        const val ALARM_CHANNEL = "keramika_alarm_v3"
        /** Канал проверок реальности (системный звук уведомлений). */
        const val RC_CHANNEL = "keramika_rc_v1"

        /** Одноразовая уборка каналов прошлых версий (в рамках процесса). */
        private var channelsCleanedUp = false

        /**
         * Действие для догона пропущенного срабатывания: ставится на
         * PendingIntent вместо обычного, поэтому [android.app.PendingIntent]
         * считает его отдельным будильником и он не затирает основной.
         */
        const val ACTION_MISSED = "com.wetidom.keramika.action.ALARM_MISSED"
    }
}
