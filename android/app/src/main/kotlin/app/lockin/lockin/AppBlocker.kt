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

    /**
     * Resumed activities ("package/class" to package), oldest first. Opening
     * Recents resumes the launcher without pausing the app underneath; picking
     * that app again only pauses the launcher. The newest one left is in front.
     */
    private val resumed = LinkedHashMap<String, String>()
    @Volatile private var lastSource: String? = null
    @Volatile private var system: Pair<Long, Set<String>>? = null
    @Volatile private var blockedSince = 0L
    @Volatile private var notedAt = 0L

    /** Set by the Play Store edition's instant blocking service while Android runs it. */
    @Volatile var instantConnected = false

    /**
     * The app whose block screen last closed, and when. Apps leaving the
     * front can still send a window event (YouTube does); until usage history
     * shows the app opened again, instant blocking ignores its events.
     */
    @Volatile private var closed: Pair<String, Long>? = null

    /** When the user last left a blocked app with "Go home". */
    @Volatile var leftAt = 0L
        private set
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
    /** Strict mode is locked: uninstall screens are blockable, Stop is ignored. */
    @Volatile var strictLocked = false
    private val uninstallers = setOf("com.android.packageinstaller", "com.google.android.packageinstaller")

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

    /** Applies new activity events since the last scan. */
    private fun scan(context: Context) {
        val now = System.currentTimeMillis()
        // Seed from the last day once, then re-read a short overlap in case an
        // event becomes queryable slightly after its timestamp. Replaying events
        // in order is idempotent for the set of resumed activities.
        val from = if (scannedUntil == 0L) now - 86_400_000L else scannedUntil - 5_000L
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = manager.queryEvents(from, now) ?: return
        val event = UsageEvents.Event()
        var changed = 0L
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val activity = "${event.packageName}/${event.className}"
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    resumed.remove(activity)
                    resumed[activity] = event.packageName
                }
                UsageEvents.Event.ACTIVITY_PAUSED, UsageEvents.Event.ACTIVITY_STOPPED -> resumed.remove(activity)
                UsageEvents.Event.DEVICE_SHUTDOWN, UsageEvents.Event.DEVICE_STARTUP -> resumed.clear()
                else -> continue
            }
            // Older history must not undo a newer instant blocking note.
            if (event.timeStamp >= notedAt) changed = event.timeStamp
        }
        if (changed > 0L) {
            foreground = resumed.values.lastOrNull()
            // The app whose block screen closed is in front again.
            closed?.let { (pkg, at) -> if (pkg == foreground && changed > at) closed = null }
        }
        scannedUntil = now
    }

    private val launchable = java.util.concurrent.ConcurrentHashMap<String, Boolean>()

    /**
     * An app's window came to the front (Play Store edition's instant
     * blocking). Usage history records the switch a moment later, so this
     * takes effect first. Only launchable apps and home screens count: the
     * notification shade, keyboards and dialogs keep the app behind them.
     */
    fun noteForeground(context: Context, pkg: String) {
        if (closed?.first == pkg) return
        val counts = launchable.getOrPut(pkg) {
            context.packageManager.getLaunchIntentForPackage(pkg) != null ||
                pkg in systemPackages(context)
        }
        if (!counts) return
        val ime = (context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
            .enabledInputMethodList.any { it.packageName == pkg }
        if (!ime && pkg != "com.android.systemui") {
            notedAt = System.currentTimeMillis()
            foreground = pkg
        }
    }

    /** The restrictable foreground app, or null. Background thread only. */
    fun detect(context: Context): String? {
        if (!TrackingRuntime.enabled(context) || !permitted(context) || !UsageReader.hasAccess(context)) {
            foreground = null
            scannedUntil = 0L
            resumed.clear()
            return null
        }
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (!power.isInteractive || keyguard.isKeyguardLocked) return null
        scan(context)
        val pkg = foreground
        return when {
            pkg == null -> null
            strictLocked && pkg in uninstallers -> "android:$pkg"
            pkg in systemPackages(context) -> null
            else -> "android:$pkg"
        }
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

    /**
     * Covers [target] with the block screen: "Not now, [name].", how far
     * through the block it is ([label], from [from] until [until], epoch
     * milliseconds; [from] is -1 for a daily limit, which ends at midnight),
     * and the way back. Without a span, [message] says why instead.
     */
    fun showBlock(
        context: Context, target: String, message: String, askAi: Boolean = false,
        name: String? = null, label: String? = null, from: Long = -1L, until: Long = -1L,
    ) {
        require(target.startsWith("android:")) { "Only Android apps can be blocked here." }
        check(permitted(context)) { "Allow Grindset to display over other apps to block apps." }
        if (lastSource != target) return
        if (overlay != null && blocked == target) return
        hideBlock(context)
        val app = context.applicationContext
        val pkg = target.removePrefix("android:")
        val density = app.resources.displayMetrics.density
        fun dp(value: Number) = (value.toFloat() * density).toInt()
        val inter = try { Typeface.createFromAsset(app.assets, "flutter_assets/assets/fonts/Inter.ttf") } catch (_: Exception) { Typeface.DEFAULT }
        fun font(weight: Int) = if (Build.VERSION.SDK_INT >= 28) Typeface.create(inter, weight, false) else if (weight >= 600) Typeface.create(inter, Typeface.BOLD) else inter
        val ink = Color.rgb(245, 245, 247)
        val secondary = Color.rgb(177, 177, 183)
        val green = Color.rgb(48, 209, 88)
        val content = LinearLayout(app).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(28), dp(24), dp(20))
            setBackgroundColor(Color.rgb(9, 9, 10))
        }
        fun space(weight: Float) = View(app).apply {
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, weight)
        }
        fun text(value: String, size: Float, color: Int, weight: Int = 400) = TextView(app).apply {
            text = value; textSize = size; setTextColor(color); typeface = font(weight)
        }
        // Grows with the screen; the column itself stays phone-width.
        val column = LinearLayout(app).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
        }
        column.addView(space(3f))
        try {
            val icon = android.widget.ImageView(app).apply {
                setImageDrawable(app.packageManager.getApplicationIcon(pkg))
                layoutParams = LinearLayout.LayoutParams(dp(52), dp(52)).apply { bottomMargin = dp(28) }
            }
            column.addView(icon)
        } catch (_: Exception) {
            // No icon: the name says which app it is.
        }
        val appName = name ?: try {
            app.packageManager.getApplicationLabel(app.packageManager.getApplicationInfo(pkg, 0)).toString()
        } catch (_: Exception) { pkg }
        val long = appName.length > 14
        column.addView(text("Not now,\n$appName.", if (long) 38f else 48f, ink, 700).apply {
            letterSpacing = if (long) -0.034f else -0.037f
            setLineSpacing(0f, 0.95f)
            maxLines = 4
        })
        var update: (() -> Unit)? = null
        if (label != null && until > 0L) {
            val bar = LinearLayout(app).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(10)).apply { topMargin = dp(32) }
            }
            val done = View(app).apply { setBackgroundColor(green) }
            val gap = View(app)
            val rest = View(app).apply { setBackgroundColor(Color.rgb(48, 48, 52)) }
            bar.addView(done); bar.addView(gap); bar.addView(rest)
            column.addView(bar)
            val row = LinearLayout(app).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(14) }
            }
            row.addView(text(label, 15f, ink, 600).apply {
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            })
            val detail = text("", 15f, secondary).apply { gravity = Gravity.END }
            row.addView(detail)
            column.addView(row)
            val ends = android.text.format.DateFormat.getTimeFormat(app).format(java.util.Date(until))
            val refresh = {
                val now = System.currentTimeMillis()
                val part = if (from < 0L) 1f else ((now - from).toFloat() / (until - from).coerceAtLeast(1L)).coerceIn(0f, 1f)
                done.layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, part)
                gap.layoutParams = LinearLayout.LayoutParams(if (part in 0.001f..0.999f) dp(3) else 0, LinearLayout.LayoutParams.MATCH_PARENT)
                rest.layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f - part)
                val minutes = ((until - now) / 60_000L).toInt()
                detail.text = when {
                    from < 0L -> "Opens again tomorrow"
                    minutes < 1 -> "Under a minute left · ends $ends"
                    minutes < 60 -> "$minutes min left · ends $ends"
                    minutes % 60 == 0 -> "${minutes / 60} hr left · ends $ends"
                    else -> "${minutes / 60} hr ${minutes % 60} min left · ends $ends"
                }
                bar.requestLayout()
            }
            refresh()
            update = refresh
        } else {
            column.addView(text(message, 15f, secondary).apply {
                setLineSpacing(0f, 1.3f)
                setPadding(0, dp(32), 0, 0)
            })
        }
        column.addView(space(4f))
        fun action(label: String, primary: Boolean, click: () -> Unit) = Button(app).apply {
            text = label; typeface = font(if (primary) 600 else 400); isAllCaps = false
            textSize = if (primary) 16f else 14f
            minHeight = dp(if (primary) 54 else 48)
            stateListAnimator = null
            setTextColor(if (primary) Color.rgb(29, 29, 31) else secondary)
            backgroundTintList = null
            background = RippleDrawable(
                ColorStateList.valueOf(if (primary) Color.argb(40, 0, 0, 0) else Color.argb(30, 255, 255, 255)),
                if (primary) GradientDrawable().apply { cornerRadius = dp(11).toFloat(); setColor(ink) } else null,
                GradientDrawable().apply { cornerRadius = dp(11).toFloat(); setColor(Color.WHITE) },
            )
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(6) }
            setOnClickListener { click() }
        }
        column.addView(action("Back to work", true) {
            hideBlock(app)
            // Usage history and checks already under way still describe the
            // blocked app; neither may bring the block back over home.
            leftAt = System.currentTimeMillis()
            notedAt = leftAt
            foreground = null
            lastSource = null
            TrackingRuntime.dismissRequested()
            app.startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        })
        column.addView(if (askAi) action("Need it? Ask AI for a few minutes", false) {
            // Grindset asks for the reason; opening it hides this screen.
            TrackingRuntime.passRequested(target)
            app.packageManager.getLaunchIntentForPackage(app.packageName)?.let {
                app.startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        } else View(app).apply { layoutParams = LinearLayout.LayoutParams(1, dp(54)) })
        content.addView(column)
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
        update?.let { refresh ->
            val tick = object : Runnable {
                override fun run() {
                    if (overlay !== content) return
                    refresh()
                    content.postDelayed(this, 15_000L)
                }
            }
            content.postDelayed(tick, 15_000L)
        }
    }

    fun hideBlock(context: Context) {
        overlay?.let { windows(context).removeView(it) }
        val pkg = blocked?.removePrefix("android:")
        if (pkg != null && blockedSince > 0L) recordPeriod(context, pkg, blockedSince, System.currentTimeMillis())
        if (pkg != null && overlay != null) closed = pkg to System.currentTimeMillis()
        overlay = null
        blocked = null
        blockedSince = 0L
    }
}
