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
import android.provider.Settings
import java.util.LinkedHashSet
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
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
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmSchedulerPlugin.registerWith(flutterEngine, applicationContext)

        // Уведомления НЕ отменяем — fullScreenIntent только что показал
        // alarm-нотификацию с играющим звуком. cancelAlarmNotifications()
        // здесь убьёт и звук, и WakeTaskScreen. Отмена происходит только
        // по stopAlarmSound из Dart после решения задачи.

        // Надёжная тактильная отдача: системный HapticFeedback на MIUI часто
        // подавлен настройками «обратной связи», поэтому бьём напрямую через
        // Vibrator с короткими VibrationEffect (VIBRATE-пермишен уже есть).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HAPTICS_CHANNEL)
            .setMethodCallHandler { call, result ->
                val vib = getSystemService(VIBRATOR_SERVICE) as Vibrator
                val effect = when (call.method) {
                    // Усилено: раньше импульсы 8–32 мс на слабом вибромоторе
                    // Redmi Note 12 были практически неощутимы.
                    "select" -> VibrationEffect.createOneShot(30, 200)
                    "light" -> VibrationEffect.createOneShot(50, 255)
                    "medium" -> VibrationEffect.createOneShot(75, 255)
                    "heavy" -> VibrationEffect.createOneShot(95, 255)
                    else -> null
                }
                if (effect != null) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vib.vibrate(effect)
                    } else {
                        @Suppress("DEPRECATION")
                        vib.vibrate(20)
                    }
                }
                result.success(true)
            }

        // Полноэкранные уведомления (поверх блокировки): проверяем, выдано ли
        // разрешение, чтобы не открывать настройки MIUI при каждом включении
        // переключателя — только когда разрешения реально нет.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.wetidom.keramika/fullscreen",
        ).setMethodCallHandler { call, result ->
            if (call.method == "canUseFullScreenIntent") {
                val canUse = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
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
                result.success(canUse)
            } else {
                result.notImplemented()
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
                    AlarmReceiver.stopActiveSound()
                    cancelAlarmNotifications()
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        // Уведомления НЕ отменяем здесь — fullScreenIntent только что
        // открыл приложение и убийство нотификации закроет WakeTaskScreen.
        // Отмена происходит только когда пользователь решил задачу
        // (через stopAlarmSound в Dart-канале).

        val payload = intent.getStringExtra("payload")
        if (!payload.isNullOrEmpty()) {
            methodChannel?.invokeMethod("onNewAlarmPayload", payload)
            intent.removeExtra("payload")
        }
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
