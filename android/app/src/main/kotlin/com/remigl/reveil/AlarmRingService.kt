package com.remigl.reveil

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import java.util.Calendar
import java.util.Locale

/**
 * Service au premier plan qui fait sonner le réveil : son en boucle sur le
 * canal « alarme », vibration, notification avec bouton « Arrêter » et écran
 * de réveil plein écran ([AlarmActivity]).
 */
class AlarmRingService : Service() {

    companion object {
        const val ACTION_STOP = "com.remigl.reveil.STOP"

        /** Diffusé (en interne) quand la sonnerie s'arrête. */
        const val ACTION_STOPPED = "com.remigl.reveil.STOPPED"

        private const val CHANNEL_ID = "reveil_alarme"
        private const val NOTIFICATION_ID = 1

        /** Sécurité : la sonnerie s'arrête seule au bout de 10 minutes. */
        private const val MAX_RING_MS = 10 * 60 * 1000L

        @Volatile
        var isRinging: Boolean = false
            private set

        fun timeLabel(): String {
            val now = Calendar.getInstance()
            return String.format(
                Locale.ROOT,
                "%02d:%02d",
                now.get(Calendar.HOUR_OF_DAY),
                now.get(Calendar.MINUTE),
            )
        }
    }

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private val autoStop = Runnable { stopSelf() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        // Obligatoire dans les secondes qui suivent startForegroundService().
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        if (!isRinging) {
            isRinging = true
            acquireWakeLock()
            startSound()
            startVibration()
            handler.postDelayed(autoStop, MAX_RING_MS)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(autoStop)
        try {
            player?.stop()
        } catch (_: IllegalStateException) {
        }
        player?.release()
        player = null
        vibrator?.cancel()
        vibrator = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        isRinging = false
        // Ferme l'écran de réveil s'il est affiché.
        sendBroadcast(Intent(ACTION_STOPPED).setPackage(packageName))
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        val power = getSystemService(PowerManager::class.java)
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "reveil:sonnerie").apply {
            acquire(MAX_RING_MS + 10_000L)
        }
    }

    private fun startSound() {
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        ensureAudibleAlarmVolume()

        player = try {
            // Son embarqué dans l'application (res/raw/reveil.wav).
            MediaPlayer().apply {
                setAudioAttributes(attributes)
                resources.openRawResourceFd(R.raw.reveil).use { fd ->
                    setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
                }
                isLooping = true
                prepare()
                start()
            }
        } catch (_: Exception) {
            // Secours : la sonnerie de réveil par défaut du téléphone.
            try {
                MediaPlayer().apply {
                    setAudioAttributes(attributes)
                    setDataSource(this@AlarmRingService, Settings.System.DEFAULT_ALARM_ALERT_URI)
                    isLooping = true
                    prepare()
                    start()
                }
            } catch (_: Exception) {
                null
            }
        }
    }

    /** Un réveil au volume zéro ne réveille personne : on le remonte. */
    private fun ensureAudibleAlarmVolume() {
        try {
            val audio = getSystemService(AudioManager::class.java)
            if (audio.getStreamVolume(AudioManager.STREAM_ALARM) == 0) {
                val max = audio.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                audio.setStreamVolume(AudioManager.STREAM_ALARM, maxOf(1, max * 6 / 10), 0)
            }
        } catch (_: Exception) {
            // Refusé par certains modes « Ne pas déranger » : on garde le volume actuel.
        }
    }

    private fun startVibration() {
        try {
            @Suppress("DEPRECATION")
            val v = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator ?: return
            if (!v.hasVibrator()) return
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .build()
            @Suppress("DEPRECATION")
            v.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 600, 600), 0), attributes)
            vibrator = v
        } catch (_: Exception) {
        }
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Réveil",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Affiché quand le réveil sonne"
            // Le son et la vibration sont gérés par le service lui-même.
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)

        val immutable = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val fullScreen = PendingIntent.getActivity(
            this,
            2,
            Intent(this, AlarmActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION,
            ),
            immutable,
        )
        val stop = PendingIntent.getService(
            this,
            3,
            Intent(this, AlarmRingService::class.java).setAction(ACTION_STOP),
            immutable,
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_alarm)
            .setContentTitle("Réveil")
            .setContentText("Il est ${timeLabel()}")
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(fullScreen)
            // Écran verrouillé ou éteint : ouvre directement l'écran de réveil.
            .setFullScreenIntent(fullScreen, true)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, R.drawable.ic_alarm),
                    "Arrêter",
                    stop,
                ).build(),
            )
            .build()
    }
}
