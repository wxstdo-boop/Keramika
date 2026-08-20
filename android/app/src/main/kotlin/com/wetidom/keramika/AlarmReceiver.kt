package com.wetidom.keramika

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
        val wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "keramika:alarm")
        wakeLock.acquire(120_000)

        try {
            val id = intent.getIntExtra("alarm_id", 0)
            val title = intent.getStringExtra("title") ?: "Alarm"
            val body = intent.getStringExtra("body") ?: ""
            val channelId = intent.getStringExtra("channel_id") ?: "keramika_alarm"
            val channelName = intent.getStringExtra("channel_name") ?: "Alarms"
            val rawSoundName = intent.getStringExtra("sound_name") ?: "alarm_default"
            // Map Dart sound names to Android raw resource names
            val soundName = when (rawSoundName) {
                "Default" -> "alarm_default"
                "Gentle" -> "gentle"
                "Classic" -> "classic"
                "Digital" -> "digital"
                "Nature" -> "nature"
                "Custom" -> "alarm_default"
                else -> rawSoundName
            }
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
            logToFile(context, "ALARM FIRED id=$id title=$title sound=$soundName")

            // Звук идёт ТОЛЬКО через канал уведомления — системный плеер,
            // не убивается при блокировке, переживает убийство процесса.
            // Вибрация напрямую.
            if (vibrate) doVibrate(context)

            // Уведомление — единственный источник звука.
            showNotification(context, id, title, body, channelId, channelName, soundName, vibrate, payload, fullscreen, customPath)

            // Стартуем Activity ТОЛЬКО для payload-будильников (не rc).
            // Используем NEW_TASK + SINGLE_TOP (без CLEAR_TOP!) чтобы:
            //  — если приложение в фоне — оно откроется
            //  — если WakeTaskScreen уже виден — не сбросит его
            //    (Dart-код проверит _wakeScreenShowing и проигнорирует)
            if (payload != "rc") {
                try {
                    val i = Intent(context, MainActivity::class.java)
                    i.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    i.putExtra("payload", payload)
                    context.startActivity(i)
                } catch (_: Exception) {}
            }

            // Перепланируем следующий.
            if (repeatDays.isNotEmpty()) rescheduleNext(context, id, intent, hour, minute, repeatDays)
        } finally {
            try { wakeLock.release() } catch (_: Exception) {}
        }
    }

    // ── Вибрация ──────────────────────────────────────────

    @Suppress("DEPRECATION")
    private fun doVibrate(ctx: Context) {
        try {
            val p = longArrayOf(0, 800, 400, 800, 400, 800)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator.vibrate(VibrationEffect.createWaveform(p, 0))
            } else {
                (ctx.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator)
                    .vibrate(VibrationEffect.createWaveform(p, 0))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Vibrate failed: $e")
        }
    }

    // ── Уведомление ───────────────────────────────────────

    private fun showNotification(
        ctx: Context, id: Int, title: String, body: String,
        channelId: String, channelName: String, soundName: String,
        vibrate: Boolean, payload: String, fullscreen: Boolean,
        customPath: String?
    ) {
        // Единый стабильный канал — без пересоздания при каждом срабатывании.
        val stableChannelId = "keramika_alarm_v2"

        val soundUri = if (!customPath.isNullOrEmpty()) Uri.parse("file://$customPath")
        // Системный звук уведомлений (проверки реальности): берём URI,
        // который пользователь выбрал в настройках телефона.
        else if (soundName == "system_default")
            android.media.RingtoneManager.getDefaultUri(
                android.media.RingtoneManager.TYPE_NOTIFICATION
            )
        else Uri.parse("android.resource://${ctx.packageName}/raw/$soundName")

        val audioAttr = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        // Канал: IMPORTANCE_HIGH + звук + вибрация. Не удаляем/пересоздаём,
        // чтобы не сбивать AlarmManager и звук на MIUI/HyperOS.
        // ВАЖНО: если soundUri битый (ресурс удалён/переименован) — канал
        // НЕ должен ронять приёмник: будильник обязан хотя бы показать
        // уведомление. Всё обёрнуто в try/catch с фолбэком на тихий канал.
        try {
            val channel = NotificationChannel(stableChannelId, channelName, NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Alarm notifications"
                setSound(soundUri, audioAttr)
                enableVibration(vibrate)
                if (vibrate) vibrationPattern = longArrayOf(0, 800, 400, 800, 400, 800)
                enableLights(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        } catch (e: Exception) {
            // Звук из res/raw может отсутствовать (resource shrinker
            // переименовал/вырезал файлы) — будильник НЕ должен молчать.
            // Падаем на системный звук будильника (RingtoneManager), иначе
            // уведомление уйдёт тихим и пользователь проспит.
            Log.e(TAG, "Channel with sound failed: $e — falling back to system alarm sound")
            try {
                val fallbackUri = android.media.RingtoneManager.getDefaultUri(
                    android.media.RingtoneManager.TYPE_ALARM
                ) ?: android.media.RingtoneManager.getDefaultUri(
                    android.media.RingtoneManager.TYPE_NOTIFICATION
                )
                val fallback = NotificationChannel(
                    stableChannelId, channelName, NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Alarm notifications"
                    if (fallbackUri != null) setSound(fallbackUri, audioAttr)
                    enableVibration(vibrate)
                    if (vibrate) vibrationPattern = longArrayOf(0, 800, 400, 800, 400, 800)
                }
                (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .createNotificationChannel(fallback)
            } catch (_: Exception) {}
        }

        // Intent для fullScreenIntent и contentIntent — ОДИН на двоих.
        val tapIntent = Intent(ctx, MainActivity::class.java)
        tapIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        tapIntent.putExtra("payload", payload)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_UPDATE_CURRENT
        val pi = PendingIntent.getActivity(ctx, id, tapIntent, flags)

        // Билдер: звук через канал + setSound для совместимости.
        val builder = NotificationCompat.Builder(ctx, stableChannelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(false)
            .setOngoing(true)
            .setContentIntent(pi)
            .setFullScreenIntent(pi, fullscreen)
            .setSound(soundUri)
            .setColor(0xFFFDF2F6.toInt())

        if (vibrate) {
            builder.setVibrate(longArrayOf(0, 800, 400, 800, 400, 800))
            builder.setDefaults(NotificationCompat.DEFAULT_VIBRATE)
        }

        try {
            NotificationManagerCompat.from(ctx).notify(id, builder.build())
            Log.d(TAG, "Notification id=$id channel=$stableChannelId sound=$soundUri")
            logToFile(ctx, "NOTIFICATION POSTED id=$id channel=$stableChannelId")
        } catch (e: SecurityException) {
            Log.e(TAG, "Notification failed: $e")
            logToFile(ctx, "NOTIFICATION FAILED id=$id error=$e")
        }
    }

    // ── Постоянный лог ─────────────────────────────────────

    private fun logToFile(ctx: Context, msg: String) {
        try {
            val dir = ctx.getExternalFilesDir(null)
            if (dir != null) {
                val f = java.io.File(dir, "alarm_fire_log.txt")
                val ts = java.text.SimpleDateFormat(
                    "yyyy-MM-dd HH:mm:ss",
                    java.util.Locale.US,
                ).format(java.util.Date())
                f.appendText("$ts $msg\n")
            }
        } catch (_: Exception) {}
    }

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
        } catch (e: Exception) {
            Log.e(TAG, "Could not reschedule id=$alarmId", e)
        }
    }

    private fun dow(cal: Calendar): Int = when (cal.get(Calendar.DAY_OF_WEEK)) {
        Calendar.MONDAY -> 1; Calendar.TUESDAY -> 2; Calendar.WEDNESDAY -> 3
        Calendar.THURSDAY -> 4; Calendar.FRIDAY -> 5; Calendar.SATURDAY -> 6
        Calendar.SUNDAY -> 7; else -> 0
    }

    companion object {
        private const val TAG = "AlarmReceiver"

        fun stopActiveSound() {
            // Звук теперь только через канал уведомления — останавливается когда уведомление закрывается.
        }
    }
}
