package app.lockin.lockin

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
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

    fun maybeStart(context: Context, askNotifications: Boolean = false) {
        if (!enabled(context) || serviceRunning(context)) return
        if (!UsageReader.hasAccess(context)) {
            setError(context, "Usage Access is required for background tracking.")
            return
        }
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            setError(context, "Allow notifications so background tracking stays visible.")
            val prefs = preferences(context)
            if (askNotifications && !prefs.getBoolean("notification_asked", false)) {
                activity.get()?.let {
                    prefs.edit().putBoolean("notification_asked", true).apply()
                    it.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST)
                }
            }
            return
        }
        try {
            val intent = Intent(context, TrackingService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
            else context.startService(intent)
            setError(context, null)
        } catch (error: Exception) {
            setError(context, "Background tracking could not start: ${error.message}")
        }
    }

    fun stop(context: Context) {
        preferences(context).edit().putBoolean("enabled", false).remove("error").apply()
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
                        preferences(context).edit().putBoolean("enabled", true)
                            .putBoolean("notification_asked", false).apply()
                        maybeStart(context, askNotifications = true)
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
                    executor.execute {
                        try {
                            val records = UsageReader.read(context, from, until)
                            main.post { result.success(records) }
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
