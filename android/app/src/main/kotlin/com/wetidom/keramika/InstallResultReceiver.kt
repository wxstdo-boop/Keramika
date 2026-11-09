package com.wetidom.keramika

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * Результат установки из сессии PackageInstaller (см.
 * MainActivity.installViaSession).
 *
 * Система присылает сюда статус по PendingIntent, который мы отдали в
 * Session.commit(). Приёмник вызывается ДВА раза:
 *  1. сразу после commit — со статусом STATUS_PENDING_USER_ACTION, если
 *     системе нужно подтверждение пользователя. Тогда в Intent лежит
 *     EXTRA_INTENT — системный экран «Установить приложение?», который мы
 *     обязаны показать сами;
 *  2. после решения пользователя — с настоящим итогом (SUCCESS / FAILURE…).
 *
 * Второй вызов после УСПЕШНОЙ установки приходит уже в НОВЫЙ процесс: старый
 * система гасит, подменяя приложение. Поэтому результат не держим только в
 * памяти — кладём его в SharedPreferences (см. [UpdaterBridge]), иначе
 * интерфейс не узнает ни об успехе, ни о провале.
 */
class InstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_INSTALL_RESULT) return

        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, STATUS_UNKNOWN)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        Log.i(TAG, "install result: status=$status message=$message")

        // Система просит показать своё подтверждение — запускаем его и
        // ждём второго вызова с настоящим итогом. Без этого шага установка
        // просто не начнётся (у приложения нет INSTALL_PACKAGES).
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            val confirm = extractIntent(intent)
            if (confirm != null) {
                confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    context.startActivity(confirm)
                } catch (e: Exception) {
                    Log.e(TAG, "cannot launch install confirmation: $e")
                    UpdaterBridge.deliver(
                        context,
                        PackageInstaller.STATUS_FAILURE,
                        e.message,
                    )
                }
            } else {
                Log.w(TAG, "PENDING_USER_ACTION without EXTRA_INTENT")
            }
            return
        }

        UpdaterBridge.deliver(context, status, message)
    }

    @Suppress("DEPRECATION")
    private fun extractIntent(intent: Intent): Intent? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_INTENT)
        }

    companion object {
        const val TAG = "InstallResultReceiver"
        const val ACTION_INSTALL_RESULT = "com.wetidom.keramika.INSTALL_RESULT"
        const val STATUS_UNKNOWN = -999
    }
}

/**
 * Мост между приёмником результата и Dart-каналом обновления.
 *
 * Итог установки может прийти в трёх состояниях приложения, и во всех он
 * обязан дойти до интерфейса:
 *  * приложение на экране — канал жив, отдаём статус сразу (push);
 *  * приложение свёрнуто, но процесс жив — статус ждёт до возврата;
 *  * после УСПЕШНОЙ установки процесс другой — Dart ещё не подписан,
 *    результат забирается pull-вызовом consumeInstallResult.
 *
 * Буфером служит SharedPreferences, а не поле в памяти: процесс, принявший
 * финальный broadcast, может быть одноразовым (система поднимает его ровно
 * под доставку). Запись в prefs переживает и этот случай, и обычный возврат.
 * Один и тот же статус не покажется дважды — он стирается в момент передачи.
 */
object UpdaterBridge {
    private const val PREFS = "keramika_updater"
    private const val KEY_STATUS = "pending_install_status"
    private const val KEY_MESSAGE = "pending_install_message"
    private const val KEY_TIME = "pending_install_time"

    @Volatile
    private var channel: MethodChannel? = null

    @Volatile
    private var dartReady = false

    @Volatile
    private var appContext: Context? = null

    fun attach(context: Context, ch: MethodChannel) {
        appContext = context.applicationContext
        channel = ch
        flush()
    }

    fun detach() {
        channel = null
        dartReady = false
    }

    /** Кладёт итог в буфер и, если Dart уже слушает, отдаёт его сразу. */
    fun deliver(context: Context, status: Int, message: String?) {
        store(context.applicationContext, status, message)
        flush()
    }

    /** Забирает придержанный результат. Вызывается из Dart после подписки. */
    fun consume(context: Context): Map<String, Any?>? {
        dartReady = true
        val ctx = context.applicationContext
        val stored = read(ctx) ?: return null
        clear(ctx)
        return stored
    }

    /**
     * Читает результат, если он не протух. Старше [MAX_AGE_MS] — считаем
     * мусором прошлого запуска и молча стираем: показывать «обновление
     * отменено» через сутки после события бессмысленно.
     */
    private fun read(ctx: Context): Map<String, Any?>? {
        val p = prefs(ctx)
        if (!p.contains(KEY_STATUS)) return null
        val time = p.getLong(KEY_TIME, 0L)
        if (time != 0L && System.currentTimeMillis() - time > MAX_AGE_MS) {
            clear(ctx)
            return null
        }
        return mapOf(
            "status" to p.getInt(KEY_STATUS, InstallResultReceiver.STATUS_UNKNOWN),
            "message" to p.getString(KEY_MESSAGE, null),
        )
    }

    private fun flush() {
        val ch = channel ?: return
        if (!dartReady) return
        val ctx = appContext ?: return
        val stored = read(ctx) ?: return
        clear(ctx)
        // MethodChannel.invokeMethod обязан идти из главного потока.
        Handler(Looper.getMainLooper()).post {
            try {
                ch.invokeMethod("onInstallResult", stored)
            } catch (e: Exception) {
                Log.e(InstallResultReceiver.TAG, "cannot deliver install result: $e")
            }
        }
    }

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun store(ctx: Context, status: Int, message: String?) {
        prefs(ctx).edit()
            .putInt(KEY_STATUS, status)
            .putString(KEY_MESSAGE, message)
            .putLong(KEY_TIME, System.currentTimeMillis())
            .commit()
    }


    private fun clear(ctx: Context) {
        prefs(ctx).edit()
            .remove(KEY_STATUS)
            .remove(KEY_MESSAGE)
            .remove(KEY_TIME)
            .commit()
    }

    /** Максимальный возраст придержанного результата — 15 минут. */
    private const val MAX_AGE_MS = 15 * 60 * 1000L
}
