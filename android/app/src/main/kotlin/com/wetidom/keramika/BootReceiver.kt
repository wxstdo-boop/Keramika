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
                // После ОБНОВЛЕНИЯ приложения пропущенное утро догонять не
                // нужно: телефон не выключался, и человек вполне мог
                // будильник уже прослушать. После РЕБУТА — нужно: это ровно
                // тот случай «выключил телефон ночью, утром будильник молчал».
                val isUpdate = intent.action == ACTION_MY_PACKAGE_REPLACED
                rescheduleFromManifest(context, recoverMissed = !isUpdate)
                launchApp(context)
            }
        }
    }

    private fun rescheduleFromManifest(ctx: Context, recoverMissed: Boolean) {
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

                    // Пропущенный слот ищем ДО сдвига `next` в будущее.
                    val missedAt =
                        if (recoverMissed && days.isNotEmpty() && payload != "rc") {
                            missedOccurrence(hour, minute, days, now)
                        } else {
                            null
                        }

                    if (days.isEmpty()) {
                        // Одноразовый будильник: если его время уже прошло —
                        // он либо уже сработал, либо «просрочен» (например,
                        // телефон был выключен). Не воскрешаем.
                        if (!next.after(now)) {
                            AlarmLog.write(
                                ctx,
                                "BOOT SKIP id=$code one-shot expired ${hour}:${"%02d".format(minute)}",
                            )
                            continue
                        }
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

                    if (arm(am, ctx, code, buildIntent(ctx, code, title, body, soundName, vibrate, payload, hour, minute, repeatDays, customPath, null), next.timeInMillis, "BOOT")) {
                        scheduled++
                    }

                    missedAt?.let { was ->
                        // Догон: звеним через минуту после включений, чтобы
                        // система успела поднять статус-бар, и подписываем
                        // уведомление как пропущенное.
                        val ring = now.timeInMillis + MISSED_DELAY_MS
                        val i = buildIntent(
                            ctx, code, title, body, soundName, vibrate, payload,
                            hour, minute, repeatDays, customPath,
                            AlarmReceiver.ACTION_MISSED,
                        )
                        if (arm(am, ctx, code, i, ring, "BOOT-MISSED")) {
                            AlarmLog.write(
                                ctx,
                                "BOOT MISS-RECOVER id=$code was=${AlarmLog.time(was)} ring=${AlarmLog.time(ring)}",
                            )
                        }
                    }
                } catch (_: Exception) {}
            }
            Log.d(TAG, "Boot rescheduled $scheduled alarms")
            val nextArmed = am.nextAlarmTime()
            AlarmLog.write(
                ctx,
                "BOOT RESCHEDULED $scheduled alarms nextAlarm=" +
                    if (nextArmed > 0) AlarmLog.time(nextArmed) else "none",
            )
        } catch (e: Exception) {
            Log.e(TAG, "rescheduleFromManifest failed", e)
        }
    }

    /**
     * Единая постановка: setAlarmClock, когда точные будильники разрешены,
     * иначе idle-safe вариант. Каждый исход уходит в чёрный ящик — без строки
     * SCHEDULE нельзя доказать, что будильник вообще был взведён.
     */
    private fun arm(
        am: AlarmManager,
        ctx: Context,
        code: Int,
        intent: Intent,
        atMillis: Long,
        tag: String,
    ): Boolean {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        else
            PendingIntent.FLAG_UPDATE_CURRENT
        val pi = PendingIntent.getBroadcast(ctx, code, intent, flags)
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
        return try {
            if (exact) {
                am.setAlarmClock(AlarmManager.AlarmClockInfo(atMillis, pi), pi)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pi)
            } else {
                am.set(AlarmManager.RTC_WAKEUP, atMillis, pi)
            }
            AlarmLog.write(
                ctx,
                "$tag SCHEDULE id=$code fire=${AlarmLog.time(atMillis)} " +
                    "api=${if (exact) "alarmClock" else "whileIdle"}",
            )
            true
        } catch (e: Exception) {
            Log.e(TAG, "Reschedule failed code=$code", e)
            AlarmLog.write(
                ctx,
                "$tag SCHEDULE FAILED id=$code error=${e.javaClass.simpleName}: ${e.message}",
            )
            false
        }
    }

    @Suppress("SpellCheckingInspection")
    private fun buildIntent(
        ctx: Context,
        code: Int,
        title: String,
        body: String,
        soundName: String,
        vibrate: Boolean,
        payload: String,
        hour: Int,
        minute: Int,
        repeatDays: String,
        customPath: String?,
        action: String?,
    ): Intent = Intent(ctx, AlarmReceiver::class.java).apply {
        if (action != null) this.action = action
        putExtra("alarm_id", code)
        putExtra("title", title)
        putExtra("body", body)
        putExtra("channel_id", "keramika_alarm")
        putExtra("channel_name", "Alarms")
        putExtra("sound_name", soundName)
        putExtra("vibrate", vibrate)
        putExtra("payload", payload)
        putExtra("fullscreen", true)
        putExtra("hour", hour)
        putExtra("minute", minute)
        putExtra("repeat_days", repeatDays)
        if (customPath != null) putExtra("custom_sound_path", customPath)
    }

    /**
     * Последний ПРОШЕДШИЙ слот повторяющегося будильника, если он случился не
     * позже [MISSED_GRACE_MS] назад. Иначе null — будильник либо ещё не
     * наступал, либо просрочен слишком давно, чтобы будить человека сейчас.
     */
    private fun missedOccurrence(
        hour: Int,
        minute: Int,
        days: List<Int>,
        now: Calendar,
    ): Long? {
        val cand = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        for (back in 0..7) {
            if (!cand.after(now) && days.contains(dow(cand))) {
                val late = now.timeInMillis - cand.timeInMillis
                return if (late in 0 until MISSED_GRACE_MS) cand.timeInMillis else null
            }
            cand.add(Calendar.DAY_OF_YEAR, -1)
        }
        return null
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

        /**
         * Как давно мог пройти пропущенный будильник, чтобы догон имел смысл.
         * Раньше 06:30 утра телефон включили в 11:00 — звонить уже поздно и
         * только раздражать.
         */
        private const val MISSED_GRACE_MS = 3 * 60 * 60_000L

        /** Пауза после загрузки, чтобы система успела поднять интерфейс. */
        private const val MISSED_DELAY_MS = 45_000L
    }
}
