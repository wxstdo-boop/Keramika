package com.wetidom.keramika

import android.app.NotificationManager
import android.content.ContentValues
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.wetidom.keramika/alarm_payload"
    private val SECURE_CHANNEL = "com.wetidom.keramika/secure"
    private val HAPTICS_CHANNEL = "com.wetidom.keramika/haptics"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmSchedulerPlugin.registerWith(flutterEngine, applicationContext)

        // Когда установлен PIN — скрываем содержимое приложения из «недавних»
        // и скриншотов (FLAG_SECURE): в переключателе задач телефон показывает
        // размытую/пустую заглушку вместо приватных данных.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    val secure = call.argument<Boolean>("secure") ?: false
                    runOnUiThread {
                        if (secure) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }

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

            // Remove previous file with the same name so we overwrite cleanly.
            resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.MediaColumns._ID),
                "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?",
                arrayOf(fileName, "$relativePath/"),
                null,
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idCol)
                    resolver.delete(
                        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                        "${MediaStore.MediaColumns._ID}=?",
                        arrayOf(id.toString()),
                    )
                }
            }

            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("MediaStore insert returned null")
            resolver.openOutputStream(uri)?.use { out ->
                out.write(bytes)
                out.flush()
            } ?: throw IllegalStateException("Could not open output stream")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
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
            val ids = ArrayList<Long>()
            resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(
                    MediaStore.MediaColumns._ID,
                    MediaStore.MediaColumns.DISPLAY_NAME,
                    MediaStore.MediaColumns.DATE_ADDED,
                ),
                "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?",
                arrayOf("$relativePath/", "keramika%"),
                "${MediaStore.MediaColumns.DATE_ADDED} DESC",
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                while (cursor.moveToNext()) {
                    ids.add(cursor.getLong(idCol))
                }
            }
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
