package app.lockin.lockin

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/** Keeps the single Dart collector and durable SQLite journal alive after UI close. */
class TrackingService : Service() {
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())
    private val permissionCheck = object : Runnable {
        override fun run() {
            if (!TrackingRuntime.enabled(this@TrackingService)) {
                stopSelf()
                return
            }
            val issue = TrackingRuntime.permissionError(this@TrackingService)
            if (issue != null) {
                TrackingRuntime.suspendCollection(this@TrackingService, issue)
                stopSelf()
                return
            }
            handler.postDelayed(this, 1_000L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacks(permissionCheck)
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP || !TrackingRuntime.enabled(this)) {
            TrackingRuntime.stop(this)
            stopSelf()
            return START_NOT_STICKY
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Background activity tracking", NotificationManager.IMPORTANCE_LOW))
        }
        val issue = TrackingRuntime.permissionError(this)
        if (issue != null) {
            TrackingRuntime.suspendCollection(this, issue)
            stopSelf()
            return START_NOT_STICKY
        }
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, TrackingService::class.java).setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder.setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setContentTitle("Grindset activity tracking")
            .setContentText("Foreground app time is saved on this device.")
            .setContentIntent(open).setOngoing(true).setShowWhen(false)
            .addAction(Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel, "Stop tracking", stop).build())
            .build()
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else startForeground(NOTIFICATION_ID, notification)
        } catch (error: Exception) {
            TrackingRuntime.suspendCollection(this, "Background tracking could not start: ${error.message}")
            stopSelf()
            return START_NOT_STICKY
        }
        TrackingRuntime.beginCollection(this)
        handler.removeCallbacks(permissionCheck)
        handler.postDelayed(permissionCheck, 1_000L)
        // Post after startForeground: engine startup must not delay the service deadline.
        handler.post { TrackingRuntime.engine(this) }
        return START_STICKY
    }

    companion object {
        const val CHANNEL = "lockin_tracking"
        private const val NOTIFICATION_ID = 4301
        private const val STOP = "app.lockin.STOP_TRACKING"
    }
}

class TrackingBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            TrackingRuntime.maybeStart(context)
        }
    }
}
