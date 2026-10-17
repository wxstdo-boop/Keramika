package com.wetidom.keramika

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * «Звонок» будильника: громкое looping-воспроизведение, которое НЕ зависит
 * ни от full-screen-intent права, ни от настроек канала уведомления.
 *
 * Почему он нужен: на этом телефоне (HyperOS/Android 15) замеры показали
 * `USE_FULL_SCREEN_INTENT: ignore` и `FSI CHECK granted=false` — экран
 * будильника открыть нельзя, а звук канала — ОДИН короткий сигнал: если
 * пользователь его не заметил, телефон молчит дальше и он просыпает.
 * Сервис гудит, пока его не остановят (Dart вызывает stopAlarmSound после
 * решения задачи пробуждения) или пока не истечёт [MAX_RING_MS].
 *
 * Пускается ТОЛЬКО из [AlarmReceiver] — то есть из broadcast, полученного по
 * точному AlarmManager-будильнику. Это одно из немногих исключений,
 * разрешающих старт foreground-сервиса из фона на Android 12+.
 */
class AlarmForegroundService : Service() {

    private var player: MediaPlayer? = null
    private var ringtone: android.media.Ringtone? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private var vibrating = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        // Регистрируем приёмник остановки: так при остановке остановятся ВСЕ
        // одновременно запущенные экземпляры сервиса, а не только один
        // (ctx.stopService() с простым Intent остановил бы не более одного).
        val i = StopReceiver()
        stopReceiver = i
        try {
            registerReceiver(i, IntentFilter(ACTION_STOP))
        } catch (_: Exception) {}
    }


    private var stopReceiver: StopReceiver? = null

    private inner class StopReceiver : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            if (intent.action == ACTION_STOP) {
                stopEverything()
                stopSelf()
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopEverything()
            stopSelf(startId)
            return START_NOT_STICKY
        }

        // foreground-уведомление ОБЯЗАНО появиться до истечения ~10 с после
        // startForegroundService — иначе система убьёт процесс.
        startRingingForeground(intent)

        val soundName = intent?.getStringExtra("sound_name") ?: "alarm_default"
        val customPath = intent?.getStringExtra("custom_sound_path")
        val vibrate = intent?.getBooleanExtra("vibrate", true) ?: true

        acquireWakeLock()
        playLoop(soundName, customPath)
        if (vibrate) startVibrationLoop()

        // Страховка от «забыли выключить»: телефон не должен звонить вечно.
        handler.postDelayed({ stopEverything() }, MAX_RING_MS)
        return START_NOT_STICKY
    }

    private fun startRingingForeground(intent: Intent?) {
        val title = intent?.getStringExtra("title") ?: "Будильник"
        val body = intent?.getStringExtra("body") ?: ""
        val payload = intent?.getStringExtra("payload") ?: ""

        // Низкая важность: это НЕ второе «всплывающее» уведомление, а
        // табличка, держащая сервис живым. Звук — у MediaPlayer ниже.
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                // FIX (дубли в шторке): канал FGS держит сервис звонка живым,
                // но LOW + ongoing делает вторую карточку («Звонок будильника»)
                // рядом с основной (из AlarmReceiver). MIN убирает badge и
                // звук у FGS-таблички — сервис и звук MediaPlayer от этого
                // не зависят.
                NotificationChannel(CHANNEL, "Звонок будильника", NotificationManager.IMPORTANCE_MIN).apply {
                    description = "Непрерывный сигнал будильника"
                    setSound(null, null)
                    enableVibration(false)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                },
            )
        }

        val tap = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("payload", payload)
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(tap)
            .setOngoing(true)
            .build()

        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                else 0,
            )
        } catch (e: Exception) {
            // На некоторых прошивках specialUse-тип недоступен: звук всё
            // равно нужен, поэтому пробуем без типа.
            try {
                startForeground(NOTIFICATION_ID, notification)
            } catch (e2: Exception) {
                AlarmLog.write(this, "RING FGS FAILED error=${e2.javaClass.simpleName}")
            }
        }
    }

    // ── Звук ──────────────────────────────────────────────

    private fun playLoop(soundName: String, customPath: String?) {
        // Путь из старых версий мог указать на файл, которого уже нет
        // (кэш file_picker вычищен, источник удалён). Тогда играем
        // ВСТРОЕННЫЙ ресурс по soundName, а не системный дзынь телефона:
        // «свой» файл пропал — но выбранный в приложении звук обязан
        // остаться тем же.
        val usableCustom = customPath?.takeIf { path ->
            if (path.isEmpty()) return@takeIf false
            val f = try {
                if (path.startsWith("file://")) java.io.File(Uri.parse(path).path) else java.io.File(path)
            } catch (_: Exception) {
                return@takeIf false
            }
            f.exists() && f.canRead()
        }
        if (customPath != null && !customPath.isEmpty() && usableCustom == null) {
            AlarmLog.write(this, "RING CUSTOM MISSING path=$customPath → sound=$soundName")
        }
        val uri = try {
            if (usableCustom != null) {
                Uri.parse(if (usableCustom.startsWith("file://")) usableCustom else "file://$usableCustom")
            } else {
                Uri.parse("android.resource://$packageName/raw/$soundName")
            }
        } catch (e: Exception) {
            AlarmLog.write(this, "RING URI EMPTY path=$customPath sound=$soundName error=${e.javaClass.simpleName}")
            null
        }
        if (uri != null) {
            try {
                player = MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                    setDataSource(this@AlarmForegroundService, uri)
                    isLooping = true
                    prepare()
                    start()
                }
                AlarmLog.write(this, "RING PLAYER OK uri=$uri")
                return
            } catch (e: Exception) {
                AlarmLog.write(
                    this,
                    "RING PLAYER FAILED uri=$uri error=${e.javaClass.simpleName}",
                )
            }
        }

        // Файл недоступен (пользователь удалил свой рингтон) — системный
        // звук будильника, лишь бы телефон звонил.
        try {
            val def = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val r = RingtoneManager.getRingtone(this, def)
            r?.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            r?.play()
            ringtone = r
            // Системный рингтон не зацикливается — перезапускаем, как только
            // он доиграл, иначе звонок кончится через несколько секунд.
            handler.postDelayed(object : Runnable {
                override fun run() {
                    val rt = ringtone ?: return
                    try {
                        if (!rt.isPlaying) rt.play()
                    } catch (_: Exception) {}
                    handler.postDelayed(this, RING_RETRY_MS)
                }
            }, RING_RETRY_MS)
        } catch (e: Exception) {
            AlarmLog.write(this, "RING FALLBACK FAILED error=${e.javaClass.simpleName}")
        }
    }

    // ── Вибрация ──────────────────────────────────────────

    @Suppress("DEPRECATION")
    private fun startVibrationLoop() {
        vibrating = true
        handler.postDelayed(object : Runnable {
            override fun run() {
                if (!vibrating) return
                try {
                    val pattern = longArrayOf(0, 700, 300, 700, 300, 700)
                    val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                            .defaultVibrator
                    } else {
                        getSystemService(VIBRATOR_SERVICE) as Vibrator
                    }
                    // См. AlarmReceiver.doVibrate: без USAGE_ALARM HyperOS
                    // режет вибрацию как «UNKNOWN = OFF».
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        vib.vibrate(
                            VibrationEffect.createWaveform(pattern, -1),
                            android.os.VibrationAttributes.Builder()
                                .setUsage(android.os.VibrationAttributes.USAGE_ALARM)
                                .build(),
                        )
                    } else {
                        vib.vibrate(VibrationEffect.createWaveform(pattern, -1))
                    }
                } catch (_: Exception) {}
                handler.postDelayed(this, VIBRATE_CYCLE_MS)
            }
        }, VIBRATE_CYCLE_MS)
    }

    // ── Удержание CPU ──────────────────────────────────────

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "keramika:alarm_ring")
                .apply { acquire(MAX_RING_MS + 30_000) }
        } catch (_: Exception) {}
    }

    private fun stopEverything() {
        handler.removeCallbacksAndMessages(null)
        vibrating = false
        try {
            player?.stop()
            player?.release()
        } catch (_: Exception) {}
        player = null
        try {
            ringtone?.stop()
        } catch (_: Exception) {}
        ringtone = null
        // FIX (вибрация не гаснет на API 31+): отменять вибрацию надо тем же
        // экземпляром, на котором она запускалась. startVibrationLoop на API 31+
        // крутит её через VibratorManager.defaultVibrator, а cancel через
        // deprecated VIBRATOR_SERVICE на мультивибраторных HyperOS/MIUI брал
        // «другой» мотор — и циклическая вибрация (postDelayed, VIBRATE_CYCLE_MS)
        // продолжала гудеть до MAX_RING_MS после выключения будильника.
        @Suppress("DEPRECATION")
        try {
            val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                getSystemService(VIBRATOR_SERVICE) as Vibrator
            }
            vib.cancel()
        } catch (_: Exception) {}
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {}
        wakeLock = null
        try {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {}
        stopSelf()
    }

    override fun onDestroy() {
        try {
            stopReceiver?.let { unregisterReceiver(it) }
        } catch (_: Exception) {}
        stopEverything()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "keramika_alarm_ring"
        private const val NOTIFICATION_ID = 66667

        /** Долже звонить, чем «проспать», но и не вечно. */
        private const val MAX_RING_MS = 5 * 60_000L
        private const val RING_RETRY_MS = 1_500L
        private const val VIBRATE_CYCLE_MS = 3_500L

        const val ACTION_STOP = "com.wetidom.keramika.action.STOP_RING"

        /**
         * Запустить звонок. Вызывается из [AlarmReceiver] (broadcast по
         * точному будильнику) и из «Теста» будильника.
         */
        /**
         * Запустить звонок.
         *
         * Возвращает `false`, если система отказала в старте — на Android 12+
         * это обычное дело для фоновых сервисов (исключения жёстко
         * перечислены платформой). Принимающая сторона обязана подстраховать
         * звук уведомлением, иначе будильник окажется немым.
         */
        fun start(
            ctx: Context,
            soundName: String,
            customPath: String?,
            vibrate: Boolean,
            title: String,
            body: String,
            payload: String,
        ): Boolean {
            val i = Intent(ctx, AlarmForegroundService::class.java).apply {
                putExtra("sound_name", soundName)
                putExtra("vibrate", vibrate)
                putExtra("title", title)
                putExtra("body", body)
                putExtra("payload", payload)
                if (!customPath.isNullOrEmpty()) putExtra("custom_sound_path", customPath)
            }
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ctx.startForegroundService(i)
                } else {
                    ctx.startService(i)
                }
                true
            } catch (e: Exception) {
                AlarmLog.write(ctx, "RING START REJECTED error=${e.javaClass.simpleName}: ${e.message}")
                false
            }
        }

        /**
         * Остановить звонок (после решения задачи пробуждения / отмены).
         *
         * Всё новое — широковещательная остановка. [ctx.stopService] с
         * простым Intent остановит НЕ БОЛЕЕ одного из запущенных
         * экземпляров сервиса, и тогда второй звонок продолжит проигрываться
         * после первого (именно это было в описанной проблеме). Отправляем
         * [ACTION_STOP] широковещательно; каждый зарегистрированный в
         * сервисе экземпляр захватит его и вызовет [stopEverything] + [stopSelf].
         */
        fun stop(ctx: Context) {
            try {
                val i = Intent(ctx, AlarmForegroundService::class.java).apply {
                    action = ACTION_STOP
                }
                ctx.sendBroadcast(i)
            } catch (_: Exception) {}
        }
    }
}
