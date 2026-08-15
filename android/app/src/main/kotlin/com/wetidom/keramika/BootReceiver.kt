package com.wetidom.keramika

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.Intent.ACTION_BOOT_COMPLETED
import android.content.Intent.ACTION_MY_PACKAGE_REPLACED
import android.os.Build
import android.util.Log
import org.json.JSONArray
import java.util.Calendar

/**
 * Восстанавливает будильники после перезагрузки телефона.
 *
 * Android стирает ВСЕ AlarmManager-алармы при ребуте (как точные, так и
 * inexact). Единственный надёжный способ их вернуть — перепланировать
 * нативно из этого приёмника: манифест запланированных будильников лежит
 * в SharedPreferences (его ведёт AlarmSchedulerPlugin при каждой
 * постановке/отмене). Запуск полного Flutter-приложения для этого НЕ нужен:
 * на MIUI/HyperOS (Redmi Note 12) запуск Activity из фона после boot часто
 * блокируется, поэтому прежняя цепочка «BootReceiver → Dart-перепланировка»
 * молча не срабатывала — будильник на утро просто исчезал.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        when (intent?.action) {
            ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            ACTION_MY_PACKAGE_REPLACED -> {
                if (context == null) return
                Log.d(TAG, "Boot/update received — rescheduling alarms natively")
                rescheduleFromManifest(context)
                launchApp(context)
            }
        }
    }

    private fun rescheduleFromManifest(ctx: Context) {
        try {
            val prefs = ctx.applicationContext
                .getSharedPreferences(AlarmSchedulerPlugin.PREFS_NAME, Context.MODE_PRIVATE)
            val raw = prefs.getString(AlarmSchedulerPlugin.MANIFEST_KEY, null)
                ?: return
            val arr = JSONArray(raw)
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val now = Calendar.getInstance()
            var scheduled = 0
            for (i in 0 until arr.length()) {
                try {
                    val o = arr.getJSONObject(i)
                    val code = o.optInt("code", -1)
                    if (code < 0) continue
                    val title = o.optString("title", "Alarm")
                    val body = o.optString("body", "")
                    val hour = o.optInt("hour", 0)
                    val minute = o.optInt("minute", 0)
                    val repeatDays = o.optString("repeatDays", "")
                    val soundName = o.optString("soundName", "alarm_default")
                    val vibrate = o.optBoolean("vibrate", true)
                    val payload = o.optString("payload", "")
                    val customPath = o.optString("customSoundPath", "").ifEmpty { null }

                    val days = repeatDays.split(",").mapNotNull { it.trim().toIntOrNull() }
                    val next = Calendar.getInstance().apply {
                        set(Calendar.HOUR_OF_DAY, hour)
                        set(Calendar.MINUTE, minute)
                        set(Calendar.SECOND, 0)
                        set(Calendar.MILLISECOND, 0)
                    }
                    if (days.isEmpty()) {
                        // Одноразовый будильник: если его время уже прошло —
                        // он либо уже сработал, либо «просрочен» (например,
                        // телефон был выключен). Не воскрешаем.
                        if (!next.after(now)) continue
                    } else {
                        // Повторяющийся: ближайший будущий день из расписания.
                        if (!next.after(now) || !days.contains(dow(next))) {
                            var found = false
                            for (d in 1..14) {
                                next.add(Calendar.DAY_OF_YEAR, 1)
                                if (days.contains(dow(next))) {
                                    found = true
                                    break
                                }
                            }
                            if (!found) continue
                        }
                    }

                    val intent = Intent(ctx, AlarmReceiver::class.java)
                    intent.putExtra("alarm_id", code)
                    intent.putExtra("title", title)
                    intent.putExtra("body", body)
                    intent.putExtra("channel_id", "keramika_alarm")
                    intent.putExtra("channel_name", "Alarms")
                    intent.putExtra("sound_name", soundName)
                    intent.putExtra("vibrate", vibrate)
                    intent.putExtra("payload", payload)
                    intent.putExtra("fullscreen", true)
                    intent.putExtra("hour", hour)
                    intent.putExtra("minute", minute)
                    intent.putExtra("repeat_days", repeatDays)
                    if (customPath != null) intent.putExtra("custom_sound_path", customPath)

                    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    else
                        PendingIntent.FLAG_UPDATE_CURRENT
                    val pi = PendingIntent.getBroadcast(ctx, code, intent, flags)

                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                            !am.canScheduleExactAlarms()
                        ) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                am.setAndAllowWhileIdle(
                                    AlarmManager.RTC_WAKEUP,
                                    next.timeInMillis,
                                    pi,
                                )
                            } else {
                                am.set(AlarmManager.RTC_WAKEUP, next.timeInMillis, pi)
                            }
                        } else {
                            am.setAlarmClock(
                                AlarmManager.AlarmClockInfo(next.timeInMillis, pi),
                                pi,
                            )
                        }
                        scheduled++
                    } catch (e: Exception) {
                        Log.e(TAG, "Reschedule failed code=$code", e)
                    }
                } catch (_: Exception) {}
            }
            Log.d(TAG, "Boot rescheduled $scheduled alarms")
            logToFile(ctx, "BOOT RESCHEDULED $scheduled alarms")
        } catch (e: Exception) {
            Log.e(TAG, "rescheduleFromManifest failed", e)
        }
    }

    private fun dow(cal: Calendar): Int = when (cal.get(Calendar.DAY_OF_WEEK)) {
        Calendar.MONDAY -> 1
        Calendar.TUESDAY -> 2
        Calendar.WEDNESDAY -> 3
        Calendar.THURSDAY -> 4
        Calendar.FRIDAY -> 5
        Calendar.SATURDAY -> 6
        Calendar.SUNDAY -> 7
        else -> 0
    }

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

    private fun launchApp(context: Context) {
        val launch = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("boot_completed", true)
        }

        // Используем PendingIntent — надёжнее работает на Android 10+,
        // где startActivity() из фона может быть заблокирован.
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        else
            PendingIntent.FLAG_UPDATE_CURRENT

        val pi = PendingIntent.getActivity(context, 9999, launch, flags)
        try {
            pi.send()
            Log.d(TAG, "PendingIntent sent — app should start and reschedule alarms")
        } catch (e: Exception) {
            Log.e(TAG, "PendingIntent.send failed, trying startActivity", e)
            try {
                context.startActivity(launch)
            } catch (e2: Exception) {
                Log.e(TAG, "startActivity also failed", e2)
            }
        }
    }

    companion object {
        private const val TAG = "BootReceiver"
    }
}
