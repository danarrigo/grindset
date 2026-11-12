package app.lockin.lockin

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

/** One engine owns SQLite and authentication, with or without a Flutter activity. */
object TrackingRuntime {
    const val NOTIFICATION_PERMISSION_REQUEST = 4301
    private var cachedEngine: FlutterEngine? = null
    private var activity = WeakReference<Activity>(null)
    private var channel: MethodChannel? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun engine(context: Context, shellArgs: Array<String>? = null): FlutterEngine {
        cachedEngine?.let { return it }
        val app = context.applicationContext
        val engine = FlutterEngine(app, shellArgs)
        cachedEngine = engine
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "app.lockin/usage").also {
            it.setMethodCallHandler { call, result -> handle(app, call, result) }
        }
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        return engine
    }

    fun attach(host: Activity) {
        activity = WeakReference(host)
    }

    fun detach(host: Activity) {
        if (activity.get() === host) activity.clear()
        // A foreground service, not an invisible activity, owns background work.
        if (!enabled(host) && activity.get() == null) {
            cachedEngine?.destroy()
            cachedEngine = null
            channel = null
        }
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences("lockin_runtime", Context.MODE_PRIVATE)

    fun enabled(context: Context): Boolean = preferences(context).getBoolean("enabled", false)

    fun setError(context: Context, error: String?) {
        preferences(context).edit().putString("error", error).apply()
    }

    fun serviceRunning(context: Context): Boolean {
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        @Suppress("DEPRECATION")
        return manager.getRunningServices(Int.MAX_VALUE).any {
            it.service.className == TrackingService::class.java.name && it.foreground
        }
    }

    fun permissionError(context: Context): String? {
        if (!UsageReader.hasAccess(context)) return "Usage Access is required for background tracking."
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if ((Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) ||
            !manager.areNotificationsEnabled()) {
            return "Allow notifications so background tracking stays visible."
        }
        if (Build.VERSION.SDK_INT >= 26 &&
            manager.getNotificationChannel(TrackingService.CHANNEL)?.importance == NotificationManager.IMPORTANCE_NONE) {
            return "Allow the background activity tracking notification channel."
        }
        return null
    }

    fun beginCollection(context: Context) {
        val prefs = preferences(context)
        val edit = prefs.edit().remove("error")
        if (!prefs.contains("enabled_since")) {
            edit.putLong("enabled_since", System.currentTimeMillis())
                .putLong("collection_generation", prefs.getLong("collection_generation", 0L) + 1L)
        }
        edit.apply()
    }

    fun suspendCollection(context: Context, error: String) {
        val prefs = preferences(context)
        // Keep the opt-in, but never backfill a permission-disabled window.
        prefs.edit().remove("enabled_since").putString("error", error)
            .putLong("collection_generation", prefs.getLong("collection_generation", 0L) + 1L).apply()
        AppBlockingService.instance?.hideBlock()
        context.stopService(Intent(context, TrackingService::class.java))
    }

    private fun requestNotifications(context: Context, reviewSettings: Boolean) {
        val host = activity.get() ?: return
        val prefs = preferences(context)
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
            !prefs.getBoolean("notification_asked", false)) {
            prefs.edit().putBoolean("notification_asked", true).apply()
            host.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST)
        } else if (reviewSettings) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val intent = if (Build.VERSION.SDK_INT >= 26 &&
                manager.getNotificationChannel(TrackingService.CHANNEL)?.importance == NotificationManager.IMPORTANCE_NONE) {
                Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                    .putExtra(Settings.EXTRA_CHANNEL_ID, TrackingService.CHANNEL)
            } else if (Build.VERSION.SDK_INT >= 26) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            } else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = android.net.Uri.parse("package:${context.packageName}")
            }
            host.startActivity(intent)
        }
    }

    fun maybeStart(context: Context, askNotifications: Boolean = false) {
        if (!enabled(context)) return
        val issue = permissionError(context)
        if (issue != null) {
            suspendCollection(context, issue)
            if (askNotifications && UsageReader.hasAccess(context)) requestNotifications(context, reviewSettings = false)
            return
        }
        if (serviceRunning(context)) return
        try {
            val intent = Intent(context, TrackingService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
            else context.startService(intent)
            setError(context, null)
        } catch (error: Exception) {
            suspendCollection(context, "Background tracking could not start: ${error.message}")
        }
    }

    fun stop(context: Context) {
        val prefs = preferences(context)
        prefs.edit().putBoolean("enabled", false).remove("error").remove("enabled_since")
            .putLong("collection_generation", prefs.getLong("collection_generation", 0L) + 1L).apply()
        AppBlockingService.instance?.hideBlock()
        context.stopService(Intent(context, TrackingService::class.java))
        channel?.invokeMethod("trackingStopped", null)
    }

    private fun status(context: Context) = mapOf(
        "enabled" to enabled(context),
        "running" to serviceRunning(context),
        "blockingEnabled" to (AppBlockingService.instance != null),
        "error" to preferences(context).getString("error", null),
    )

    private fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "hasUsageAccess" -> result.success(UsageReader.hasAccess(context))
                "initializeTracking" -> {
                    val prefs = preferences(context)
                    // A stop from the notification is authoritative, even if Dart was killed.
                    if (!prefs.contains("enabled")) {
                        prefs.edit().putBoolean("enabled", call.argument<Boolean>("enabled") == true).apply()
                    }
                    maybeStart(context, askNotifications = true)
                    result.success(status(context))
                }
                "setTrackingEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") == true
                    if (enabled) {
                        preferences(context).edit().putBoolean("enabled", true).apply()
                        maybeStart(context)
                        if (permissionError(context) != null && UsageReader.hasAccess(context)) {
                            requestNotifications(context, reviewSettings = true)
                        }
                    } else stop(context)
                    result.success(status(context))
                }
                "trackingStatus" -> result.success(status(context))
                "requestUsageAccess" -> {
                    val host = checkNotNull(activity.get()) { "Open Lockin to review permissions." }
                    host.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                        data = android.net.Uri.parse("package:${context.packageName}")
                    })
                    result.success(null)
                }
                "requestBlockingAccess" -> {
                    val host = checkNotNull(activity.get()) { "Open Lockin to enable app blocking." }
                    host.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "foregroundSource" -> result.success(AppBlockingService.instance?.foregroundSource())
                "showBlock" -> {
                    val service = checkNotNull(AppBlockingService.instance) { "Enable Lockin in Accessibility settings to block apps." }
                    service.showBlock(checkNotNull(call.argument<String>("source")), call.argument<String>("message") ?: "An activity rule is active.")
                    result.success(null)
                }
                "hideBlock" -> {
                    AppBlockingService.instance?.hideBlock()
                    result.success(null)
                }
                "readUsage" -> {
                    val from = call.argument<Number>("from")?.toLong()
                    val until = call.argument<Number>("until")?.toLong()
                    require(from != null && until != null && from < until) { "Choose a positive usage range." }
                    check(enabled(context) && serviceRunning(context)) { "Background tracking must be running." }
                    permissionError(context)?.let {
                        suspendCollection(context, it)
                        throw IllegalStateException(it)
                    }
                    val prefs = preferences(context)
                    check(prefs.contains("enabled_since")) { "Background tracking has not started." }
                    val since = prefs.getLong("enabled_since", 0L)
                    val generation = prefs.getLong("collection_generation", 0L)
                    executor.execute {
                        try {
                            val records = UsageReader.read(context, maxOf(from, since), until, since)
                            main.post {
                                val issue = permissionError(context)
                                if (issue != null) suspendCollection(context, issue)
                                if (issue != null || !enabled(context) || !serviceRunning(context) ||
                                    generation != prefs.getLong("collection_generation", 0L)) {
                                    result.error("TRACKING_INTERRUPTED", "Tracking stopped or its permissions changed during the read.", null)
                                } else result.success(records)
                            }
                        } catch (error: Exception) {
                            main.post { result.error("USAGE_READ_FAILED", error.message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("ANDROID_RUNTIME_FAILED", error.message, null)
        }
    }

    fun overrideRequested() {
        channel?.invokeMethod("overrideRequested", null)
    }

    fun dismissRequested() {
        channel?.invokeMethod("dismissRequested", null)
    }
}
