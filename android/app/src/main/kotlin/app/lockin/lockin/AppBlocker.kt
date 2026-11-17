package app.lockin.lockin

import android.app.KeyguardManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Identifies the foreground app from Usage Access activity events and covers a
 * restricted app with a "Display over other apps" window. Package identifiers
 * only; never screen contents. [detect] runs on a background thread; everything
 * that touches the overlay runs on the main thread.
 */
object AppBlocker {
    private var overlay: View? = null
    @Volatile private var blocked: String? = null
    @Volatile private var foreground: String? = null
    @Volatile private var scannedUntil = 0L
    @Volatile private var lastSource: String? = null
    @Volatile private var system: Pair<Long, Set<String>>? = null
    @Volatile private var blockedSince = 0L
    private const val PERIODS = "blocked_periods"
    private const val KEEP_MS = 3 * 86_400_000L
    private val protectedPackages = setOf(
        "com.android.settings", "com.android.systemui", "com.android.permissioncontroller",
        "com.google.android.permissioncontroller", "com.android.packageinstaller",
        "com.google.android.packageinstaller",
    )

    /**
     * Android's own surfaces: never restricted and never reported as app usage.
     * Includes every installed launcher, not only the current default.
     */
    fun systemPackages(context: Context): Set<String> {
        val now = System.currentTimeMillis()
        system?.let { (at, packages) -> if (now - at < 60_000L) return packages }
        val launchers = context.packageManager.queryIntentActivities(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), 0,
        ).map { it.activityInfo.packageName }
        val inputs = (context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
            .enabledInputMethodList.map { it.packageName }
        return (protectedPackages + launchers + inputs + context.packageName).also { system = now to it }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences("lockin_runtime", Context.MODE_PRIVATE)

    /**
     * Periods when a restriction screen covered an app, as (package, start, end).
     * The covered app stays "resumed" to Android, so usage import subtracts these.
     */
    fun blockedPeriods(context: Context): List<Triple<String, Long, Long>> {
        val stored = prefs(context).getString(PERIODS, "") ?: ""
        val periods = stored.split(";").mapNotNull { item ->
            val parts = item.split(",")
            if (parts.size != 3) null
            else Triple(parts[0], parts[1].toLongOrNull() ?: return@mapNotNull null, parts[2].toLongOrNull() ?: return@mapNotNull null)
        }.toMutableList()
        val pkg = blocked?.removePrefix("android:")
        if (pkg != null && blockedSince > 0L) periods.add(Triple(pkg, blockedSince, Long.MAX_VALUE))
        return periods
    }

    private fun recordPeriod(context: Context, pkg: String, start: Long, end: Long) {
        val cutoff = end - KEEP_MS
        val kept = blockedPeriods(context).filter { it.third != Long.MAX_VALUE && it.third > cutoff }
        val all = kept + Triple(pkg, start, end)
        prefs(context).edit().putString(PERIODS, all.joinToString(";") { "${it.first},${it.second},${it.third}" }).apply()
    }

    fun permitted(context: Context): Boolean = Settings.canDrawOverlays(context)

    private fun windows(context: Context) =
        context.applicationContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager

    /** Applies new activity events since the last scan; the latest event wins. */
    private fun scan(context: Context) {
        val now = System.currentTimeMillis()
        // Seed from the last day once, then re-read a short overlap in case an
        // event becomes queryable slightly after its timestamp. Replaying events
        // in order is idempotent for "latest foreground app".
        val from = if (scannedUntil == 0L) now - 86_400_000L else scannedUntil - 5_000L
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = manager.queryEvents(from, now) ?: return
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> foreground = event.packageName
                UsageEvents.Event.ACTIVITY_PAUSED -> if (event.packageName == foreground) foreground = null
            }
        }
        scannedUntil = now
    }

    /** The restrictable foreground app, or null. Background thread only. */
    fun detect(context: Context): String? {
        if (!TrackingRuntime.enabled(context) || !permitted(context) || !UsageReader.hasAccess(context)) {
            foreground = null
            scannedUntil = 0L
            return null
        }
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (!power.isInteractive || keyguard.isKeyguardLocked) return null
        scan(context)
        val pkg = foreground
        return if (pkg == null || pkg in systemPackages(context)) null else "android:$pkg"
    }

    /** Applies a [detect] result on the main thread. */
    fun applyDetected(context: Context, source: String?) {
        lastSource = source
        if (source != blocked) hideBlock(context)
    }

    /** Grindset itself is in front: no app can be restricted behind it. */
    fun enteredLockin(context: Context) {
        foreground = context.packageName
        lastSource = null
        hideBlock(context)
        TrackingRuntime.dismissRequested()
    }

    fun showBlock(context: Context, target: String, message: String) {
        require(target.startsWith("android:")) { "Only Android apps can be blocked here." }
        check(permitted(context)) { "Allow Grindset to display over other apps to block apps." }
        if (lastSource != target) return
        if (overlay != null && blocked == target) return
        hideBlock(context)
        val app = context.applicationContext
        val density = app.resources.displayMetrics.density
        val padding = (24 * density).toInt()
        val font = try { Typeface.createFromAsset(app.assets, "flutter_assets/assets/fonts/Inter.ttf") } catch (_: Exception) { Typeface.DEFAULT }
        val content = LinearLayout(app).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(padding, padding, padding, padding)
            setBackgroundColor(Color.rgb(9, 9, 10))
        }
        fun text(value: String, size: Float) = TextView(app).apply {
            text = value; textSize = size; setTextColor(Color.WHITE); typeface = font
            gravity = Gravity.CENTER; setPadding(0, padding / 2, 0, padding / 2)
        }
        content.addView(text("App restricted", 26f))
        content.addView(text(message, 16f))
        fun action(label: String, primary: Boolean, click: () -> Unit) = Button(app).apply {
            text = label; typeface = font; textSize = 16f; isAllCaps = false
            minHeight = (48 * density).toInt()
            setPadding((16 * density).toInt(), (12 * density).toInt(), (16 * density).toInt(), (12 * density).toInt())
            setTextColor(if (primary) Color.rgb(48, 209, 88) else Color.rgb(229, 229, 234))
            backgroundTintList = null
            background = RippleDrawable(ColorStateList.valueOf(Color.argb(40, 255, 255, 255)), GradientDrawable().apply {
                cornerRadius = 12 * density
                setColor(if (primary) Color.rgb(7, 59, 29) else Color.rgb(28, 28, 30))
            }, null)
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = (8 * density).toInt() }
            setOnClickListener { click() }
        }
        content.addView(action("Go home", false) {
            hideBlock(app)
            foreground = null
            lastSource = null
            TrackingRuntime.dismissRequested()
            app.startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        })
        content.addView(action("Allow this app for 5 minutes", true) { TrackingRuntime.overrideRequested() })
        content.addView(text("Tracking stays on. Other restrictions remain active.", 13f))
        val type = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
            type, WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN, PixelFormat.OPAQUE,
        )
        windows(app).addView(content, params)
        blocked = target
        blockedSince = System.currentTimeMillis()
        overlay = content
    }

    fun hideBlock(context: Context) {
        overlay?.let { windows(context).removeView(it) }
        val pkg = blocked?.removePrefix("android:")
        if (pkg != null && blockedSince > 0L) recordPeriod(context, pkg, blockedSince, System.currentTimeMillis())
        overlay = null
        blocked = null
        blockedSince = 0L
    }
}
