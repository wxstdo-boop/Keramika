package com.wetidom.keramika

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class AlarmSchedulerPlugin private constructor(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "com.wetidom.keramika/alarm_scheduler"
        private const val TAG = "AlarmScheduler"
        // Манифест запланированных будильников в SharedPreferences.
        // BootReceiver читает его ПОСЛЕ перезагрузки телефона (система
        // стирает все AlarmManager-алармы) и перепланирует нативно — без
        // запуска Flutter-движка. На MIUI/HyperOS запуск Activity из фона
        // часто блокируется, поэтому полагаться на Dart-перепланировку
        // после boot нельзя.
        const val MANIFEST_KEY = "alarm_manifest"
        const val PREFS_NAME = "keramika_schedule"

        fun registerWith(engine: FlutterEngine, context: Context) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setMethodCallHandler(AlarmSchedulerPlugin(context))
        }
    }

    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val alarmManager = appContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scheduleAlarmClock" -> handleScheduleAlarmClock(call, result)
            "cancelAlarmClock" -> handleCancelAlarmClock(call, result)
            "isAlarmClockApiAvailable" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP)
            "canScheduleExactAlarms" -> result.success(
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && alarmManager.canScheduleExactAlarms()
            )
            "isIgnoringBatteryOptimizations" -> {
                val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(pm.isIgnoringBatteryOptimizations(context.packageName))
            }
            else -> result.notImplemented()
        }
    }

    private fun handleScheduleAlarmClock(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Int>("id") ?: 0
        val title = call.argument<String>("title") ?: "Alarm"
        val body = call.argument<String>("body") ?: ""
        val channelId = call.argument<String>("channelId") ?: "keramika_alarm"
        val channelName = call.argument<String>("channelName") ?: "Alarms"
        val rawSoundName = call.argument<String>("soundName") ?: "alarm_default"
        val soundName = mapSoundName(rawSoundName)
        val vibrate = call.argument<Boolean>("vibrate") ?: true
        val fireTimestamp = call.argument<Long>("fireTimestamp") ?: 0L
        val payload = call.argument<String>("payload") ?: ""
        val fullscreen = call.argument<Boolean>("fullscreen") ?: true
        val hour = call.argument<Int>("hour") ?: 0
        val minute = call.argument<Int>("minute") ?: 0
        val repeatDays = call.argument<String>("repeatDays") ?: ""
        val customSoundPath = call.argument<String>("customSoundPath")

        if (fireTimestamp <= 0) {
            result.error("INVALID_TIME", "Fire timestamp must be > 0", null)
            return
        }

        // Проверяем наличие SCHEDULE_EXACT_ALARM на API 31+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            Log.w(TAG, "SCHEDULE_EXACT_ALARM not granted for id=$id")
            // Всё равно пробуем — setAlarmClock может работать и без него
            // на некоторых прошивках (запасной вариант — fallback на Dart)
        }

        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra("alarm_id", id)
            putExtra("title", title)
            putExtra("body", body)
            putExtra("channel_id", channelId)
            putExtra("channel_name", channelName)
            putExtra("sound_name", soundName)
            putExtra("vibrate", vibrate)
            putExtra("payload", payload)
            putExtra("fullscreen", fullscreen)
            putExtra("hour", hour)
            putExtra("minute", minute)
            putExtra("repeat_days", repeatDays)
            if (customSoundPath != null) {
                putExtra("custom_sound_path", customSoundPath)
            }
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getBroadcast(context, id, intent, flags)

        try {
            // setAlarmClock/setExact silently fail on some MIUI builds when
            // SCHEDULE_EXACT_ALARM is not granted. In that case deliberately
            // use the inexact idle-safe API instead of returning a false alarm
            // that never fires at all.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                !alarmManager.canScheduleExactAlarms()) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        fireTimestamp,
                        pendingIntent,
                    )
                } else {
                    alarmManager.set(
                        AlarmManager.RTC_WAKEUP,
                        fireTimestamp,
                        pendingIntent,
                    )
                }
                Log.w(TAG, "Scheduled inexact alarm id=$id at $fireTimestamp")
            } else {
                val alarmClockInfo = AlarmManager.AlarmClockInfo(fireTimestamp, pendingIntent)
                alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
                Log.d(TAG, "Scheduled exact alarm id=$id at $fireTimestamp")
            }
            saveManifestEntry(
                id, title, body, hour, minute, repeatDays,
                soundName, vibrate, payload, customSoundPath,
            )
            result.success(true)
        } catch (e: SecurityException) {
            Log.e(TAG, "Exact alarm denied, falling back to idle-safe alarm for id=$id", e)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        fireTimestamp,
                        pendingIntent,
                    )
                } else {
                    alarmManager.set(AlarmManager.RTC_WAKEUP, fireTimestamp, pendingIntent)
                }
                saveManifestEntry(
                    id, title, body, hour, minute, repeatDays,
                    soundName, vibrate, payload, customSoundPath,
                )
                result.success(true)
            } catch (e2: Exception) {
                Log.e(TAG, "Fallback alarm failed for id=$id", e2)
                result.success(false)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule alarm id=$id", e)
            result.error("SCHEDULE_FAILED", e.message, null)
        }
    }

    private fun handleCancelAlarmClock(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Int>("id") ?: 0
        val intent = Intent(context, AlarmReceiver::class.java)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE
        } else {
            PendingIntent.FLAG_NO_CREATE
        }
        val pendingIntent = PendingIntent.getBroadcast(context, id, intent, flags)
        if (pendingIntent != null) {
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
            Log.d(TAG, "Cancelled alarm id=$id")
        }
        removeManifestEntry(id)
        result.success(true)
    }

    // ── Манифест для BootReceiver ────────────────────────

    private fun loadManifest(): JSONArray {
        return try {
            val raw = prefs.getString(MANIFEST_KEY, null) ?: return JSONArray()
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
    }

    private fun saveManifestEntry(
        code: Int, title: String, body: String,
        hour: Int, minute: Int, repeatDays: String,
        soundName: String, vibrate: Boolean,
        payload: String, customSoundPath: String?,
    ) {
        try {
            val arr = loadManifest()
            val keep = JSONArray()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                if (o.optInt("code", -1) != code) keep.put(o)
            }
            val e = JSONObject()
            e.put("code", code)
            e.put("title", title)
            e.put("body", body)
            e.put("hour", hour)
            e.put("minute", minute)
            e.put("repeatDays", repeatDays)
            e.put("soundName", soundName)
            e.put("vibrate", vibrate)
            e.put("payload", payload)
            if (!customSoundPath.isNullOrEmpty()) e.put("customSoundPath", customSoundPath)
            keep.put(e)
            prefs.edit().putString(MANIFEST_KEY, keep.toString()).apply()
        } catch (_: Exception) {}
    }

    private fun removeManifestEntry(code: Int) {
        try {
            val arr = loadManifest()
            val keep = JSONArray()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                if (o.optInt("code", -1) != code) keep.put(o)
            }
            prefs.edit().putString(MANIFEST_KEY, keep.toString()).apply()
        } catch (_: Exception) {}
    }

    // Map Dart sound names to Android raw resource names
    private fun mapSoundName(raw: String): String = when (raw) {
        "Default" -> "alarm_default"
        "Gentle" -> "gentle"
        "Classic" -> "classic"
        "Digital" -> "digital"
        "Nature" -> "nature"
        "Custom" -> "alarm_default"
        // Системный звук уведомлений (проверки реальности): кастомный
        // маркер, который AlarmReceiver трактует как TYPE_NOTIFICATION.
        "System" -> "system_default"
        else -> raw
    }
}
