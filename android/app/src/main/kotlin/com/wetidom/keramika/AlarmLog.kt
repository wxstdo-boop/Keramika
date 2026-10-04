package com.wetidom.keramika

import android.content.Context
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Единый «чёрный ящик» будильников: /sdcard/Android/data/<pkg>/files/alarm_fire_log.txt
 * читается через adb БЕЗ root.
 *
 * Раньше сюда писали только моменты срабатывания, и «будильник не звенел»
 * было нечем доказать: видно, что приёмник не запустился, но не видно,
 * БЫЛ ЛИ вообще взведён алгоритм. Теперь пишутся и постановка/отмена
 * (SCHEDULE/CANCEL/ARM), и решения BootReceiver (BOOT ARM/BOOT SKIP),
 * и итоговое состояние AlarmManager (NEXT ALARM=…).
 */
object AlarmLog {
    private const val FILE_NAME = "alarm_fire_log.txt"
    private const val MAX_BYTES = 256 * 1024

    fun write(ctx: Context, msg: String) {
        try {
            val dir = ctx.getExternalFilesDir(null) ?: return
            val f = java.io.File(dir, FILE_NAME)
            if (f.length() > MAX_BYTES) {
                // Хвост нужнее начала: журнал не должен вытеснить свежие утра.
                val tail = f.readLines().takeLast(400).joinToString("\n")
                f.writeText(tail + "\n")
            }
            val ts = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
            f.appendText("$ts $msg\n")
        } catch (_: Exception) {}
    }

    fun time(millis: Long): String =
        SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(millis))
}

/** Только для строк журнала: сколько будильников реально взведено в AlarmManager. */
internal fun android.app.AlarmManager.nextAlarmTime(): Long = try {
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
        nextAlarmClock?.triggerTime ?: 0L
    } else {
        0L
    }
} catch (_: Exception) {
    0L
}
