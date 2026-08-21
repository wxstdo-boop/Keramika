package com.wetidom.keramika

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat

class AlarmForegroundService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null
    private var player: MediaPlayer? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "Alarm"
        val body = intent?.getStringExtra("body") ?: ""
        val payload = intent?.getStringExtra("payload") ?: ""
        val soundName = intent?.getStringExtra("sound_name") ?: "alarm_default"
        val vibrate = intent?.getBooleanExtra("vibrate", true)
        val customPath = intent?.getStringExtra("custom_sound_path")

        Log.d(TAG, "ForegroundService started: sound=$soundName")

        // WakeLock.
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "keramika:alarm_fg")
        wakeLock?.acquire(300_000)

        // Звук.
        playSound(soundName, customPath)

        // Вибрация.
        if (vibrate == true) doVibrate()

        // Запускаем Activity НАПРЯМУЮ из Service — работает на Android 10+ даже из фона.
        try {
            val i = Intent(this, MainActivity::class.java)
            i.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            i.putExtra("payload", payload)
            startActivity(i)
            Log.d(TAG, "Activity started from service")
        } catch (e: Exception) {
            Log.e(TAG, "startActivity failed: $e")
        }

        // Показываем fullScreenIntent уведомление как fallback.
        showNotification(title, body, payload)

        // Останавливаем сервис через 3 секунды.
        android.os.Handler(mainLooper).postDelayed({
            stopSound()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }, 3000)

        return START_NOT_STICKY
    }

    // ── Звук ──────────────────────────────────────────────

    private fun playSound(soundName: String, customPath: String?) {
        val uri = if (!customPath.isNullOrEmpty()) Uri.parse("file://$customPath")
        else Uri.parse("android.resource://${packageName}/raw/$soundName")

        try {
            val mp = MediaPlayer().apply {
                setDataSource(this@AlarmForegroundService, uri)
                setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build())
                isLooping = true
                prepare()
                start()
            }
            player = mp
            Log.d(TAG, "MediaPlayer OK: $uri")
            return
        } catch (e: Exception) {
            Log.e(TAG, "MediaPlayer failed: $e")
        }

        try {
            val r = RingtoneManager.getRingtone(this, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
            r?.play()
            activeRingtone = r
        } catch (e: Exception) {
            Log.e(TAG, "Ringtone fallback failed: $e")
        }
    }

    private fun stopSound() {
        try { player?.stop(); player?.release(); player = null } catch (_: Exception) {}
        try { activeRingtone?.stop(); activeRingtone = null } catch (_: Exception) {}
    }

    // ── Вибрация ──────────────────────────────────────────

    @Suppress("DEPRECATION")
    private fun doVibrate() {
        try {
            val p = longArrayOf(0, 800, 400, 800, 400, 800)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator.vibrate(VibrationEffect.createWaveform(p, 0))
            } else {
                (getSystemService(VIBRATOR_SERVICE) as Vibrator)
                    .vibrate(VibrationEffect.createWaveform(p, 0))
            }
        } catch (_: Exception) {}
    }

    // ── Уведомление ───────────────────────────────────────

    private fun showNotification(title: String, body: String, payload: String) {
        val channelId = "keramika_alarm_fg"

        val channel = NotificationChannel(channelId, "Alarms", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Alarm notifications"
            enableLights(true)
        }
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(channel)

        val i = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("payload", payload)
        }
        val pi = PendingIntent.getActivity(this, 0, i,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(pi, true)
            .setContentIntent(pi)
            .setAutoCancel(false)
            .setOngoing(true)
            .build()

        startForeground(66666, notification)
    }

    // ── Lifecycle ─────────────────────────────────────────

    override fun onDestroy() {
        stopSound()
        try { wakeLock?.release() } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val TAG = "AlarmForegroundService"
        var activeRingtone: android.media.Ringtone? = null
    }
}
