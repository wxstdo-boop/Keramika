package com.wetidom.keramika

import android.app.NotificationManager
import android.content.ComponentName
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import java.util.LinkedHashSet
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.FileProvider
import java.security.MessageDigest
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.wetidom.keramika/alarm_payload"
    private val HAPTICS_CHANNEL = "com.wetidom.keramika/haptics"
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Edge-to-edge: контент рисуется ПОД системным статус-баром, чтобы
        // глобальное скругление углов (ClipRRect в Dart) доходило и до
        // верхних углов экрана. На MIUI/HyperOS сам по себе не включает
        // прозрачный статус-бар, поэтому сверху остаётся чёрная полоса;
        // её цвет подгоняем под фон приложения через SystemChrome в Dart.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = android.graphics.Color.TRANSPARENT
        window.navigationBarColor = android.graphics.Color.TRANSPARENT
        applyAlarmWindowFlags()
        // FIX (swipe не глушит звонок): удаление основного уведомления
        // будильника приходит через deleteIntent (см.
        // AlarmReceiver.showNotification) как Intent с action CANCEL_ALARM.
        // На холодном старте он приходит прямо в onCreate — глушим
        // фоновый звонок/вибрацию там же.
        handleCancelAlarm()
    }

    /**
     * Swipe-удаление основного уведомления будильника.
     *
     * Раньше этот Intent НЕ обрабатывался нигде: сервис звонка
     * (AlarmForegroundService: MediaPlayer + циклическая вибрация)
     * доживал до MAX_RING_MS (5 минут) после того, как пользователь
     * уже «выключил» будильник свайпом. Теперь в любом режиме
     * (onCreate / onNewIntent) звонок и вибрация гаснут немедленно.
     */
    private fun handleCancelAlarm() {
        val intent = intent ?: return
        if (intent.action != "com.wetidom.keramika.CANCEL_ALARM") return
        val aid = intent.getIntExtra("alarm_id", 0)
        Log.i("MainActivity", "CANCEL_ALARM id=$aid — stop ring + clear wake flags")
        AlarmForegroundService.stop(applicationContext)
        cancelAlarmNotifications()
        clearAlarmWakeFlags()
        intent.removeExtra("alarm_id")
        intent.action = null
    }

    /**
     * Оконные флаги для срабатывающего будильника.
     *
     * Манифестных `showWhenLocked`/`turnScreenOn` недостаточно: они
     * описывают окно, но не включают экран и не снимают ключгейрд, когда
     * активность уже была создана ранее (переиспользование задачи). Здесь
     * то же самое делается программно — это работает и при холодном старте,
     * и при `onNewIntent` по живой активности.
     *
     * `FLAG_KEEP_SCREEN_ON` намеренно висит до [clearAlarmWakeFlags]:
     * будильник, который гаснет через 5 секунд, пользователь просто
     * не успевает решить.
     */
    private fun applyAlarmWindowFlags() {
        val isAlarm = intent?.getBooleanExtra("alarm_launch", false) == true ||
            (intent?.getStringExtra("payload")?.startsWith("alarm:") == true)
        if (!isAlarm) return
        // FIX (другой путь на экран): AlarmReceiver теперь ВСЕГДА запускает
        // MainActivity при срабатывании будильника (не только при
        // fullscreen=true). Два уровня:
        //  1) ЭКРАН ВСЕГДА ЗАЖИГАЕТСЯ (turnScreenOn + keepScreenOn): будильник
        //     ни при каких настройках не остаётся молчащим — телефон проснётся
        //     и покажет экран задачи. Это и есть «другой способ» в обход
        //     FSI-права.
        //  2) СВЕРХУ БЛОКИРОВКИ (showWhenLocked + снятие ключгейрда) — только
        //     если тумблер «поверх экрана блокировки» включён (extra
        //     alarm_fullscreen). Выключил — задача откроется сразу после
        //     разблокировки (или при снятой блокировке — мгновенно),
        //     ключгейрд мы при этом не рвём.
        val overLock = intent?.getBooleanExtra("alarm_fullscreen", true) ?: true

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setTurnScreenOn(true)
            if (overLock) setShowWhenLocked(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
            if (overLock) {
                @Suppress("DEPRECATION")
                window.addFlags(
                    android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        android.view.WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
                )
            }
        }
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        if (overLock) {
            // Снимаем ключгейрд. С PIN/отпечатком система всё равно покажет
            // экран разблокировки — но НАША активность рисуется поверх него
            // (благодаря showWhenLocked), как у системного будильника.
            try {
                val km = getSystemService(KEYGUARD_SERVICE) as android.app.KeyguardManager
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    km.requestDismissKeyguard(this, null)
                }
            } catch (e: Exception) {
                Log.e("MainActivity", "requestDismissKeyguard failed: $e")
            }
        }
    }

    /** Снимает «не гасить экран» после того, как будильник отзвонил. */
    private fun clearAlarmWakeFlags() {
        try {
            // Снимаем ВСЁ, что add'илось в applyAlarmWindowFlags: иначе
            // TURN_SCREEN_ON висел бы вечно — экран телефона не гаснет
            // даже после того, как будильник уже отзвонил.
            @Suppress("DEPRECATION")
            window.clearFlags(
                android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
            )
        } catch (_: Exception) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmSchedulerPlugin.registerWith(flutterEngine, applicationContext)
        registerUpdaterChannel(flutterEngine)

        // Уведомления НЕ отменяем — fullScreenIntent только что показал
        // alarm-нотификацию с играющим звуком. cancelAlarmNotifications()
        // здесь убьёт и звук, и WakeTaskScreen. Отмена происходит только
        // по stopAlarmSound из Dart после решения задачи.

        // Надёжная тактильная отдача: системный HapticFeedback на MIUI часто
        // подавлен настройками «обратной связи», поэтому бьём напрямую через
        // Vibrator с короткими VibrationEffect (VIBRATE-пермишен уже есть).
        // Любая ошибка обязана уйти в result.error — тогда Dart-фолбэк
        // (HapticFeedback из Flutter) действительно попробует достучаться.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HAPTICS_CHANNEL)
            .setMethodCallHandler { call, result ->
                val kind = call.method
                // Длительности короткие (14-26 мс): длинные one-shot на
                // 30-95 мс, что были раньше, на линейном моторе звучали как
                // «гул», а отдача от кнопок должна быть сухой щёлкающей.
                val fallback = when (kind) {
                    "select" -> 14 to 140
                    "light" -> 17 to 160
                    "medium" -> 22 to 190
                    "heavy" -> 26 to 225
                    else -> 0 to 0
                }
                if (fallback.first == 0) {
                    result.error("UNKNOWN_KIND", call.method, null)
                    return@setMethodCallHandler
                }
                try {
                    val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                            .defaultVibrator
                    } else {
                        @Suppress("DEPRECATION")
                        getSystemService(VIBRATOR_SERVICE) as Vibrator
                    }
                    // ГЛОБАЛЬНЫЙ фикс HyperOS/MIUI: вибрация без явного
                    // назначения система относит к usage UNKNOWN, а у
                    // пользователя в «Силе вибрации» UNKNOWN и TOUCH стоят в
                    // OFF (замер dumpsys vibrator_manager на Redmi Note 12:
                    // "TOUCH = OFF, UNKNOWN = OFF", мотор при этом жив).
                    // Поэтому просим HARDWARE_FEEDBACK — его люди в life
                    // не трогают, он MEDIUM по умолчанию.
                    val effect = buildHapticEffect(vib, kind, fallback.first, fallback.second)
                    if (effect != null) {
                        // Перегрузка vibrate(effect, attributes) появилась
                        // только в Android 13 (API 33): на 12 вызов упал бы
                        // NoSuchMethodError, поэтому права USAGE_* просим
                        // ровно там, где они есть.
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            val attrs = android.os.VibrationAttributes.Builder()
                                .setUsage(android.os.VibrationAttributes.USAGE_HARDWARE_FEEDBACK)
                                .build()
                            vib.vibrate(effect, attrs)
                        } else {
                            vib.vibrate(effect)
                        }
                    } else {
                        // Android 8.0 ещё не умеет VibrationEffect.
                        @Suppress("DEPRECATION")
                        vib.vibrate(fallback.first.toLong())
                    }
                    result.success(true)
                } catch (e: Exception) {
                    Log.e("MainActivity", "haptics failed: $e")
                    result.error("VIBRATE_FAILED", e.message, null)
                }
            }

        // Полноэкранные уведомления (поверх блокировки): проверяем, выдано ли
        // разрешение, чтобы не открывать настройки MIUI при каждом включении
        // переключателя — только когда разрешения реально нет.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.wetidom.keramika/fullscreen",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                "requestUseFullScreenIntent" -> result.success(
                    // Право уже выдано — НЕ открываем настройки: этот вызов
                    // часть цепочки «Выдать», где следом открывается экран
                    // точных будильников, и два системных экрана поверх друг
                    // друга только путают.
                    if (canUseFullScreenIntent()) false else openFullScreenGrantSettings(),
                )
                // Явное действие пользователя («Открыть настройки» в строке
                // полноэкранных уведомлений) — экран нужен всегда.
                "openGrantSettings" -> result.success(openFullScreenGrantSettings())
                else -> result.notImplemented()
            }
        }

        // Контекст экрана для Ады: текст активного окна другого приложения
        // читает ScreenReaderService (Специальные возможности). Канал только
        // отвечает на вопросы «есть разрешение?» и «дай свежий снимок».
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.wetidom.keramika/screen_reader",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(isScreenReaderEnabled())
                "getScreenText" -> {
                    result.success(
                        mapOf(
                            "text" to ScreenReaderService.latestText,
                            "package" to ScreenReaderService.latestPackage,
                            "at" to ScreenReaderService.latestAt,
                        ),
                    )
                }
                "openAccessibilitySettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "openAccessibilitySettings failed: $e")
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getAlarmPayload" -> {
                    val payload = intent?.getStringExtra("payload")
                    result.success(payload)
                    intent?.removeExtra("payload")
                }
                "stopAlarmSound" -> {
                    // Пользователь решил задачу пробуждения (или отменил
                    // будильник): снимаем непрерывный звонок сервиса и
                    // убираем уведомление.
                    AlarmForegroundService.stop(applicationContext)
                    cancelAlarmNotifications()
                    // Будильник отзвонил — экран может гаснуть по обычным
                    // правилам, иначе телефон не уснёт никогда.
                    clearAlarmWakeFlags()
                    result.success(true)
                }
                "getTimeZone" -> {
                    // Returns IANA timezone ID (e.g. "Europe/Moscow") from the system
                    result.success(java.util.TimeZone.getDefault().id)
                }
                "saveToDownloads" -> {
                    try {
                        val fileName = call.argument<String>("fileName")
                            ?: throw IllegalArgumentException("fileName required")
                        val bytes = call.argument<ByteArray>("bytes")
                            ?: throw IllegalArgumentException("bytes required")
                        val subDir = call.argument<String>("subDir") ?: "Keramika"
                        val path = saveBytesToDownloads(fileName, bytes, subDir)
                        result.success(path)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "saveToDownloads failed: $e")
                        result.error("SAVE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Перезагрузка телефона (или обновление приложения) стирает все
        // одноразовые setAlarmClock — просим Dart перепланировать будильники
        // и проверки реальности. Задержка: Dart ещё регистрирует обработчик.
        maybeNotifyBootReschedule()
    }

    /** Включён ли ScreenReaderService в системных Спец. возможностях. */
    private fun isScreenReaderEnabled(): Boolean {
        return try {
            val cn = ComponentName(this, ScreenReaderService::class.java)
            // Полная форма: com.pkg/com.pkg.ScreenReaderService
            val full = cn.flattenToString()
            // Короткая форма: com.pkg/.ScreenReaderService
            val short = "$packageName/.${ScreenReaderService::class.java.simpleName}"
            val enabled = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: return false
            enabled.split(':').any { it.equals(short, true) || it.equals(full, true) }
        } catch (e: Exception) {
            Log.e("MainActivity", "isScreenReaderEnabled failed: $e")
            false
        }
    }

    /**
     * Форма тактильного импульса.
     *
     * Два уровня отдачи, и оба — короткие, чтобы ощущаться как щелчок, а не
     * как «гул» длинного one-shot на полной амплитуде:
     *
     * 1. Системные примитивы (Android 12+), НО только если мотор задаёт им
     *    НЕНУЛЕВУЮ длительность. `areAllPrimitivesSupported()` на это прошивке
     *    врёт: замер `dumpsys vibrator_manager` на Redmi Note 12 показывает
     *    `supportedPrimitives = [CLICK(0ms), TICK(0ms), ...]` — примитивы
     *    «поддерживаются», но длятся 0 мс, поэтому композиция из них даёт
     *    молчание (так хаптика и пропала целиком).
     * 2. Иначе — короткий one-shot, а для `heavy` двойной щелчок через
     *    `createWaveform(timings, -1)`: без амплитудных данных (мотор этого
     *    не умеет — `capabilities = [ON_CALLBACK, PERFORM_CALLBACK]`) паузы
     *    в таком массиве честные, и 26+46+18 мс читаются как «тук-тук».
     *
     * Заранее определённые эффекты (`EFFECT_TICK`/`EFFECT_CLICK`) убраны
     * вовсе: `supportedEffects` тут пустой список, а `createPredefined()` на
     * неподдерживаемом эффекте не бросает исключение, а молча ничего не
     * делает — то есть была бы ветка, которая гарантированно молчит.
     */
    private fun buildHapticEffect(
        vib: Vibrator,
        kind: String,
        fallbackMs: Int,
        fallbackAmp: Int,
    ): VibrationEffect? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val comp = realPrimitiveComposition(vib, kind)
            if (comp != null) return comp
        }
        if (kind == "heavy") {
            return VibrationEffect.createWaveform(
                longArrayOf(0, fallbackMs.toLong(), 46, (fallbackMs * 0.7).toLong()),
                -1,
            )
        }
        return VibrationEffect.createOneShot(
            fallbackMs.toLong(),
            amplitudeOf(vib, fallbackAmp),
        )
    }

    /**
     * Композиция примитивов, если мотор РЕАЛЬНО её воспроизводит: все
     * запрошенные примитивы поддержаны и имеют ненулевую длительность.
     * `null` — значит полагаться на короткий one-shot.
     */
    private fun realPrimitiveComposition(
        vib: Vibrator,
        kind: String,
    ): VibrationEffect? {
        val ids = intArrayOf(
            VibrationEffect.Composition.PRIMITIVE_TICK,
            VibrationEffect.Composition.PRIMITIVE_CLICK,
        )
        val durations = try {
            vib.getPrimitiveDurations(*ids)
        } catch (e: Exception) {
            Log.e("MainActivity", "getPrimitiveDurations failed: $e")
            return null
        }
        if (durations.size != ids.size || !durations.all { it > 0 }) return null
        if (!vib.areAllPrimitivesSupported(*ids)) return null

        val tick = VibrationEffect.Composition.PRIMITIVE_TICK
        val click = VibrationEffect.Composition.PRIMITIVE_CLICK
        return when (kind) {
            // «Тик» при выборе/скролле — минимальный и очень короткий.
            "select" -> VibrationEffect.startComposition()
                .addPrimitive(tick, 0.55f)
                .compose()
            "light" -> VibrationEffect.startComposition()
                .addPrimitive(tick, 0.9f)
                .compose()
            "medium" -> VibrationEffect.startComposition()
                .addPrimitive(click, 0.85f)
                .compose()
            // Тяжёлый отклик — двойной щелчок: ощущается как «стук»,
            // а не как гул той же длительности.
            "heavy" -> VibrationEffect.startComposition()
                .addPrimitive(click, 1f)
                .addPrimitive(click, 0.7f, 36)
                .compose()
            else -> null
        }
    }

    /** Часть моторов не умеет амплитуду — с ней createOneShot бросает исключение. */
    @Suppress("DEPRECATION")
    private fun amplitudeOf(vib: Vibrator, amp: Int): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !vib.hasAmplitudeControl()) {
            VibrationEffect.DEFAULT_AMPLITUDE
        } else {
            amp
        }

    /** Разрешено ли приложению показывать полноэкранные уведомления (поверх блокировки). */
    private fun canUseFullScreenIntent(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            try {
                nm.canUseFullScreenIntent()
            } catch (e: Exception) {
                Log.e("MainActivity", "canUseFullScreenIntent failed: $e")
                @Suppress("DEPRECATION")
                Settings.canDrawOverlays(this)
            }
        } else {
            @Suppress("DEPRECATION")
            Settings.canDrawOverlays(this)
        }
    }

    /**
     * Открывает ТОТ экран, где реально лежит тумблер «Полноэкранные
     * уведомления».
     *
     * С Android 14 (API 34) доступ к full-screen intent больше не является
     * обычным runtime-разрешением: это app-op `USE_FULL_SCREEN_INTENT`,
     * который по умолчанию стоит в `ignore` у всех, кроме звонилок и
     * будильников-приложений. Замер на телефоне автора (Android 15/HyperOS,
     * `cmd appops get com.wetidom.keramika`) показал ровно это:
     * `USE_FULL_SCREEN_INTENT: ignore`, а `rejectTime` совпал с моментом
     * срабатывания будильника — система отказывала ровно тогда, когда
     * AlarmReceiver вызывал setFullScreenIntent. Поэтому будильник
     * «приходит только уведомлением».
     *
     * Раньше цепочка вела пользователя в MIUI-редактор разрешений и в
     * обычные настройки уведомлений — там этого тумблера на Android 14+
     * уже нет (он переехал в отдельный список «Специальный доступ →
     * Уведомления с полноэкранным показом»). Теперь первым шагом идёт
     * прямой системный экран выдачи именно этого права.
     */
    private fun openFullScreenGrantSettings(): Boolean {
        // 1. Android 14+: персональный экран права USE_FULL_SCREEN_INTENT.
        //    Фильтр этого экрана в Settings (проверено на телефоне автора:
        //    com.android.settings/.AppManageFullScreenIntent) объявляет
        //    Scheme: "package", то есть интент БЕЗ data не резолвится вообще
        //    (`cmd package query-activities -a …` → "No activities found").
        //    Поэтому пакет кладём И в data-URI, и в extra.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
            tryStart(
                Intent(
                    "android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENT",
                    Uri.fromParts("package", packageName, null),
                ).putExtra("android.provider.extra.APP_PACKAGE", packageName),
            )
        ) {
            return true
        }
        // 2. MIUI/HyperOS: редактор разрешений приложения.
        if (tryStart(
                Intent("miui.intent.action.APP_PERM_EDITOR")
                    .setClassName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.permissions.PermissionsEditorActivity",
                    )
                    .putExtra("extra_pkgname", packageName),
            )
        ) {
            return true
        }
        // 3. Настройки уведомлений приложения.
        if (tryStart(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra("android.provider.extra.APP_PACKAGE", packageName),
            )
        ) {
            return true
        }
        // 4. Карточка приложения в системных настройках.
        return tryStart(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null)),
        )
    }

    /** Запускает экран настроек с FLAG_ACTIVITY_NEW_TASK; true если открылся. */
    private fun tryStart(i: Intent): Boolean {
        return try {
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            // Никакого resolveActivity(): с Android 11+ пакетная видимость
            // делает такие запросы бесполезными (Settings виден для запуска,
            // но не для резолва). Проверяем самим запуском.
            startActivity(i)
            true
        } catch (e: Exception) {
            Log.e("MainActivity", "open settings failed: $e")
            false
        }
    }

    private fun maybeNotifyBootReschedule() {
        if (intent?.getBooleanExtra("boot_completed", false) != true) return
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                methodChannel?.invokeMethod("onBootCompleted", null)
            } catch (e: Exception) {
                Log.e("MainActivity", "onBootCompleted invoke failed: $e")
            }
        }, 1500)
    }

    /**
     * Writes [bytes] into public Download/[subDir]/[fileName].
     * Uses MediaStore on API 29+ so no storage permission is required.
     * Returns a human-readable path string for the snackbar.
     */
    private fun saveBytesToDownloads(fileName: String, bytes: ByteArray, subDir: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/$subDir"

            // Удаляем предыдущие файлы с тем же именем, ВКЛЮЧАЯ «зависшие»
            // PENDING-строки от оборванных бэкапов: MediaStore по умолчанию
            // прячет их в запросах, и они копились — файл-менеджер показывал
            // «PENDING keramika-auto-backup.json» вместо нормального имени.
            // Ищем и точное имя, и временные имена «.pending-<id>-<имя>».
            val exactSel =
                "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?"
            val orphanSel =
                "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?"
            for (id in downloadIds(
                resolver,
                exactSel,
                arrayOf(fileName, "$relativePath/"),
                null,
                pendingMode = 1,
            ) + downloadIds(
                resolver,
                orphanSel,
                arrayOf(".pending-%$fileName", "$relativePath/"),
                null,
                pendingMode = 2,
            )) {
                resolver.delete(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    "${MediaStore.MediaColumns._ID}=?",
                    arrayOf(id.toString()),
                )
            }
            // Best-effort: физические «сироты» .pending-… (строки в MediaStore
            // уже потеряны, на MIUI удаление строки не всегда стирает файл).
            // Если доступа нет — просто пропускаем, на следующем экспорте
            // попробуем снова.
            try {
                val downloadDir =
                    File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), subDir)
                val orphans = downloadDir.listFiles { f ->
                    f.name.startsWith(".pending-") && f.name.endsWith(fileName)
                } ?: emptyArray()
                for (o in orphans) {
                    try {
                        if (o.delete()) {
                            Log.i("MainActivity", "deleted orphan ${o.name}")
                        }
                    } catch (ignored: Exception) {}
                }
            } catch (ignored: Exception) {}

            // Прямая запись БЕЗ PENDING-фазы. Раньше: insert(IS_PENDING=1) →
            // байты → снять флаг. На MIUI/HyperOS снятие флага ненадёжно
            // (update возвращает 0), и файл навсегда оставался в шторке
            // файлового менеджера как «.pending-<ts>-keramika-auto-backup.json»
            // — бэкап выглядел сломанным. Небольшой JSON пишется целиком
            // за один вызов: риск «полузаписанного» файла минимален, зато
            // бэкап ВСЕГДА появляется под нормальным именем.
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("MediaStore insert returned null")
            resolver.openOutputStream(uri)?.use { out ->
                out.write(bytes)
                out.flush()
            } ?: throw IllegalStateException("Could not open output stream")
            Log.i("MainActivity", "saveToDownloads OK: $relativePath/$fileName (${bytes.size} bytes)")
            // Ограничение: в папке остаётся НЕ БОЛЬШЕ 2 копий бэкапа
            // (авто + ручной) — старые лишние удаляются, папка не засоряется.
            trimBackupCopies(resolver, relativePath)
            return "Download/$subDir/$fileName"
        }

        @Suppress("DEPRECATION")
        val base = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val dir = File(base, subDir)
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("Cannot create ${dir.absolutePath}")
        }
        val file = File(dir, fileName)
        FileOutputStream(file).use { out ->
            out.write(bytes)
            out.flush()
        }
        return file.absolutePath
    }

    /**
     * Оставляет в Download/[relativePath] не более 2 файлов бэкапа
     * (имена начинаются с "keramika"), удаляя более старые копии.
     */
    private fun trimBackupCopies(resolver: android.content.ContentResolver, relativePath: String) {
        try {
            val selection =
                "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?"
            val args = arrayOf("$relativePath/", "keramika%")
            // Сначала обычные (новые сверху), затем «зависшие» PENDING-хвосты
            // (по определению старые) — они чистятся первыми и не забивают
            // лимит 2 копий.
            val ids = (
                downloadIds(
                    resolver,
                    selection,
                    args,
                    "${MediaStore.MediaColumns.DATE_ADDED} DESC",
                    pendingMode = 0,
                ) + downloadIds(resolver, selection, args, null, pendingMode = 2)
            ).toMutableList()
            if (ids.size > 2) {
                for (i in 2 until ids.size) {
                    resolver.delete(
                        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                        "${MediaStore.MediaColumns._ID}=?",
                        arrayOf(ids[i].toString()),
                    )
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "trimBackupCopies failed: $e")
        }
    }

    /// Собирает _ID файлов Download, подходящих под [selection].
    /// [pendingMode]: 0 — только обычные, 1 — обычные + PENDING,
    /// 2 — только PENDING. MediaStore прячет pending-строки в обычных
    /// запросах — их видно только через QUERY_ARG_MATCH_PENDING (API 30+).
    private fun downloadIds(
        resolver: android.content.ContentResolver,
        selection: String,
        args: Array<String>,
        sortOrder: String?,
        pendingMode: Int,
    ): List<Long> {
        val ids = LinkedHashSet<Long>()
        if (pendingMode != 2) {
            resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.MediaColumns._ID),
                selection,
                args,
                sortOrder,
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                while (cursor.moveToNext()) {
                    ids.add(cursor.getLong(idCol))
                }
            }
        }
        if (pendingMode != 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bundle = Bundle().apply {
                putInt(MediaStore.QUERY_ARG_MATCH_PENDING, 1)
                putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
                putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, args)
            }
            resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.MediaColumns._ID),
                bundle,
                null,
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                while (cursor.moveToNext()) {
                    ids.add(cursor.getLong(idCol))
                }
            }
        }
        return ids.toList()
    }

    /**
     * Канал автообновления `com.wetidom.keramika/updater`.
     *
     * Отдаёт версию установленного APK и ABI, разрешает ли установку из этого
     * источника, открывает системные настройки и ЗАПУСКАЕТ установку
     * скачанного APK. Перед установкой при заданном [sha256] сверяет SHA-256
     * файла с хешем из GitHub-релиза — при расхождении установку не даём.
     */
    private fun registerUpdaterChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.wetidom.keramika/updater",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "appInfo" -> {
                    try {
                        @Suppress("DEPRECATION")
                        val pi = packageManager.getPackageInfo(packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            pi.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            pi.versionCode.toLong()
                        }
                        result.success(
                            mapOf(
                                "versionCode" to code,
                                "versionName" to (pi.versionName ?: "0"),
                            ),
                        )
                    } catch (e: Exception) {
                        result.error("APP_INFO", e.message, null)
                    }
                }
                "supportedAbi" -> {
                    result.success(Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a")
                }
                "canInstall" -> {
                    val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        packageManager.canRequestPackageInstalls()
                    } else {
                        true
                    }
                    result.success(ok)
                }
                "openInstallSettings" -> {
                    try {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    val expected = call.argument<String>("sha256")
                    if (path.isNullOrEmpty()) {
                        result.error("BAD_ARGS", "path is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        if (!file.exists()) {
                            result.error("NO_FILE", path, null)
                            return@setMethodCallHandler
                        }
                        if (!expected.isNullOrEmpty()) {
                            val md = MessageDigest.getInstance("SHA-256")
                            file.inputStream().use { input ->
                                val buf = ByteArray(64 * 1024)
                                var n = input.read(buf)
                                while (n > 0) {
                                    md.update(buf, 0, n)
                                    n = input.read(buf)
                                }
                            }
                            val actual = md.digest()
                                .joinToString("") { "%02x".format(it.toInt() and 0xFF) }
                            if (!actual.equals(expected, ignoreCase = true)) {
                                result.error("HASH_MISMATCH", actual, null)
                                return@setMethodCallHandler
                            }
                        }
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            file,
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_ACTIVITY_NEW_TASK,
                            )
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "installApk failed: $e")
                        result.error("INSTALL", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Активность уже жива (приложение было на экране) — флаги
        // «поверх блокировки / не гасить экран» нужно ставить заново,
        // в onCreate они уже не попадут.
        applyAlarmWindowFlags()

        // Уведомления НЕ отменяем здесь — fullScreenIntent только что
        // открыл приложение и убийство нотификации закроет WakeTaskScreen.
        // Отмена происходит только когда пользователь решил задачу
        // (через stopAlarmSound в Dart-канале).

        val payload = intent.getStringExtra("payload")
        if (!payload.isNullOrEmpty()) {
            methodChannel?.invokeMethod("onNewAlarmPayload", payload)
            intent.removeExtra("payload")
        }
        // Свайп-удаление основного уведомления (см. handleCancelAlarm):
        // в hot-режиме приходит сюда, глушим звонок/вибрацию немедленно.
        handleCancelAlarm()
        // Приложение уже было запущено, а телефон перезагрузился —
        // сигнализируем Dart, чтобы перепланировал будильники.
        if (intent.getBooleanExtra("boot_completed", false)) {
            maybeNotifyBootReschedule()
        }
    }

    private fun cancelAlarmNotifications() {
        try {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            // Отменяем все уведомления с категорией ALARM.
            nm.activeNotifications
                .filter { it.notification.category == "alarm" }
                .forEach { NotificationManagerCompat.from(this).cancel(it.id) }
        } catch (e: Exception) {
            Log.e("MainActivity", "Cancel notifications failed: $e")
        }
    }
}
