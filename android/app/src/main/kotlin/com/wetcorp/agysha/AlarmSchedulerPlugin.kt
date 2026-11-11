package com.wetcorp.agysha

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
        private const val CHANNEL = "com.wetcorp.agysha/alarm_scheduler"
        private const val TAG = "AlarmScheduler"
        // Манифест запланированных будильников в SharedPreferences.
        // BootReceiver читает его ПОСЛЕ перезагрузки телефона (система
        // стирает все AlarmManager-алармы) и перепланирует нативно — без
        // запуска Flutter-движка. На MIUI/HyperOS запуск Activity из фона
        // часто блокируется, поэтому полагаться на Dart-перепланировку
        // после boot нельзя.
        const val MANIFEST_KEY = "alarm_manifest"
        const val PREFS_NAME = "keramika_schedule"

        /** Ключ списка прозвеневших одноразовых будильников (id.hashCode). */
        const val FIRED_ONESHOT_KEY = "fired_one_shots"

        fun registerWith(engine: FlutterEngine, context: Context) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setMethodCallHandler(AlarmSchedulerPlugin(context))
        }

        /**
         * Отмечает одноразовый будильник прозвеневшим. Зовёт [AlarmReceiver]
         * в момент срабатывания (repeatDays пуст). Dart читает список через
         * `consumeFiredOneShots` и гасит такие будильники — иначе «один раз»
         * превращалось в «каждый день»: перепланировка считает ближайшее
         * будущее время и взводит будильник заново.
         */
        fun markOneShotFired(context: Context, code: Int) {
            try {
                val prefs = context.applicationContext
                    .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val raw = prefs.getString(FIRED_ONESHOT_KEY, null)
                val arr = if (raw != null) JSONArray(raw) else JSONArray()
                for (i in 0 until arr.length()) {
                    if (arr.optInt(i, -1) == code) return
                }
                arr.put(code)
                prefs.edit().putString(FIRED_ONESHOT_KEY, arr.toString()).apply()
            } catch (_: Exception) {}
        }

        /**
         * Убирает будильник из манифеста загрузки (статически — из
         * [AlarmReceiver], где экземпляра плагина нет). Зовётся, когда
         * одноразовый будильник отзвонил: держать его в манифесте значит
         * дать BootReceiver взвести его заново после перезагрузки.
         */
        fun removeManifestEntryFor(context: Context, code: Int) {
            try {
                val prefs = context.applicationContext
                    .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val raw = prefs.getString(MANIFEST_KEY, null) ?: return
                val arr = JSONArray(raw)
                val keep = JSONArray()
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    if (o.optInt("code", -1) != code) keep.put(o)
                }
                prefs.edit().putString(MANIFEST_KEY, keep.toString()).apply()
            } catch (_: Exception) {}
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
            // Ближайший взведённый будильник по мнению самой системы. Нужен,
            // чтобы Dart-перепланировка могла ДОКАЗАТЬ постановку: молчащий
            // будильник — это либо «мы не поставили», либо «система убрала».
            "nextAlarmTime" -> result.success(alarmManager.nextAlarmTime())
            // Ключи ОДНОРАЗОВЫХ будильников, которые уже прозвенели. Их
            // записывает AlarmReceiver в момент срабатывания. Читаем и
            // очищаем: Dart гасит такие будильники, иначе «один раз» тихо
            // превращается в «каждый день» (Dart-перепланировка считает
            // ближайшее будущее время и взводит будильник заново).
            "consumeFiredOneShots" -> result.success(consumeFiredOneShots())
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
                AlarmLog.write(
                    appContext,
                    "SCHEDULE id=$id api=whileIdle fire=${AlarmLog.time(fireTimestamp)} " +
                        "exactPerm=false title=${title.take(28)}",
                )
            } else {
                val alarmClockInfo = AlarmManager.AlarmClockInfo(fireTimestamp, pendingIntent)
                alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
                Log.d(TAG, "Scheduled exact alarm id=$id at $fireTimestamp")
                AlarmLog.write(
                    appContext,
                    "SCHEDULE id=$id api=alarmClock fire=${AlarmLog.time(fireTimestamp)} " +
                        "exactPerm=true title=${title.take(28)}",
                )
            }
            saveManifestEntry(
                id, title, body, hour, minute, repeatDays,
                soundName, vibrate, payload, customSoundPath,
            )
            result.success(true)
        } catch (e: SecurityException) {
            Log.e(TAG, "Exact alarm denied, falling back to idle-safe alarm for id=$id", e)
            AlarmLog.write(
                appContext,
                "SCHEDULE DENIED id=$id error=${e.javaClass.simpleName} — пробую whileIdle",
            )
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
                AlarmLog.write(
                    appContext,
                    "SCHEDULE FAILED id=$id error=${e2.javaClass.simpleName}",
                )
                result.success(false)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule alarm id=$id", e)
            AlarmLog.write(
                appContext,
                "SCHEDULE FAILED id=$id error=${e.javaClass.simpleName}",
            )
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
            AlarmLog.write(appContext, "CANCEL id=$id")
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

    /**
     * Читает и очищает список прозвеневших одноразовых будильников.
     * Возвращает ключи (id.hashCode) — Dart гасит их в модели.
     */
    private fun consumeFiredOneShots(): List<Int> {
        return try {
            val raw = prefs.getString(FIRED_ONESHOT_KEY, null) ?: return emptyList()
            val arr = JSONArray(raw)
            val out = ArrayList<Int>(arr.length())
            for (i in 0 until arr.length()) {
                out.add(arr.getInt(i))
            }
            prefs.edit().remove(FIRED_ONESHOT_KEY).apply()
            out
        } catch (_: Exception) {
            emptyList()
        }
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
