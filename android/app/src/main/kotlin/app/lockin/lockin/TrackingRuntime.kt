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
import android.view.accessibility.AccessibilityManager
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
        AppBlocker.hideBlock(context)
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
        AppBlocker.hideBlock(context)
        context.stopService(Intent(context, TrackingService::class.java))
        channel?.invokeMethod("trackingStopped", null)
    }

    private fun status(context: Context) = mapOf(
        "enabled" to enabled(context),
        "running" to serviceRunning(context),
        "blockingEnabled" to AppBlocker.permitted(context),
        "instantAvailable" to instantBlocking(context, enabledOnly = false),
        "instantEnabled" to instantBlocking(context, enabledOnly = true),
        "error" to preferences(context).getString("error", null),
    )

    /**
     * Whether this build has the Play Store edition's instant blocking service,
     * and whether Android is actually running it.
     */
    private fun instantBlocking(context: Context, enabledOnly: Boolean): Boolean {
        // Only the service knows: AccessibilityManager's enabled list is cached
        // per process, and the Accessibility setting can list the service while
        // Android runs nothing (seen on a vivo phone after a reinstall).
        if (enabledOnly) return AppBlocker.instantConnected
        val manager = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        return manager.installedAccessibilityServiceList
            .any { it.resolveInfo.serviceInfo.packageName == context.packageName }
    }

    private val recheck = Runnable { channel?.invokeMethod("foregroundChanged", null) }

    /**
     * Another app came to the front (Play Store edition). Check rules now, and
     * again shortly after, because Android can record the switch in usage
     * history a moment after the window appears.
     */
    fun foregroundChanged() {
        main.post {
            main.removeCallbacks(recheck)
            channel?.invokeMethod("foregroundChanged", null)
            main.postDelayed(recheck, 250L)
            main.postDelayed(recheck, 700L)
        }
    }

    private fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "saveExport" -> ExportFile.save(context, activity.get(),
                    checkNotNull(call.argument<String>("path")), checkNotNull(call.argument<String>("name")), result)
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
                    val host = checkNotNull(activity.get()) { "Open Grindset to review permissions." }
                    host.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                        data = android.net.Uri.parse("package:${context.packageName}")
                    })
                    result.success(null)
                }
                "openInstantBlocking" -> {
                    val host = checkNotNull(activity.get()) { "Open Grindset to turn on instant blocking." }
                    host.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "requestBlockingAccess" -> {
                    val host = checkNotNull(activity.get()) { "Open Grindset to enable app blocking." }
                    host.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                        data = android.net.Uri.parse("package:${context.packageName}")
                    })
                    result.success(null)
                }
                "setStrictLock" -> {
                    AppBlocker.strictLocked = call.argument<Boolean>("locked") == true
                    result.success(null)
                }
                "installedApps" -> executor.execute {
                    // Apps with a home-screen icon, by name, for picking in Rules.
                    // Launchers, keyboards and Grindset itself are never blocked.
                    val pm = context.packageManager
                    val skip = AppBlocker.systemPackages(context)
                    val apps = pm.queryIntentActivities(
                        Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0,
                    ).filter { it.activityInfo.packageName !in skip }
                        .associate { it.activityInfo.packageName to it.loadLabel(pm).toString() }
                    main.post { result.success(apps) }
                }
                "appDetails" -> {
                    val packages = checkNotNull(call.argument<List<String>>("packages"))
                    executor.execute {
                        val details = packages.associateWith { AppDetails.load(context, it) }.filterValues { it != null }
                        main.post { result.success(details) }
                    }
                }
                "foregroundSource" -> executor.execute {
                    val asked = System.currentTimeMillis()
                    // Usage-event queries are binder calls: keep them off the UI thread.
                    val detected = try { AppBlocker.detect(context) } catch (_: Exception) { null }
                    main.post {
                        // A check that began before "Go home" is out of date.
                        val source = if (asked < AppBlocker.leftAt) null else detected
                        AppBlocker.applyDetected(context, source)
                        result.success(source)
                    }
                }
                "showBlock" -> {
                    AppBlocker.showBlock(context, checkNotNull(call.argument<String>("source")), call.argument<String>("message") ?: "An activity rule is active.", call.argument<Boolean>("askAi") == true)
                    result.success(null)
                }
                "openApp" -> {
                    val pkg = checkNotNull(call.argument<String>("package"))
                    val launch = checkNotNull(context.packageManager.getLaunchIntentForPackage(pkg)) { "This app can't be opened." }
                    context.startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                "hideBlock" -> {
                    AppBlocker.hideBlock(context)
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

    /** The block screen of [source] asked Grindset to ask an AI for time. */
    fun passRequested(source: String) {
        channel?.invokeMethod("passRequested", source)
    }

    fun dismissRequested() {
        channel?.invokeMethod("dismissRequested", null)
    }
}
