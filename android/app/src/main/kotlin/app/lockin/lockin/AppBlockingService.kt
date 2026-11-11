package app.lockin.lockin

import android.accessibilityservice.AccessibilityService
import android.app.KeyguardManager
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.PowerManager
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** Package-only events; never request or traverse a window's content tree. */
class AppBlockingService : AccessibilityService() {
    private var source: String? = null
    private var overlay: View? = null
    private var blocked: String? = null
    private val overlayWindows get() = getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val protectedPackages = setOf(
        "com.android.settings", "com.android.systemui", "com.android.permissioncontroller",
        "com.google.android.permissioncontroller", "com.android.packageinstaller",
        "com.google.android.packageinstaller",
    )

    override fun onServiceConnected() {
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (!TrackingRuntime.enabled(this)) { source = null; hideBlock(); return }
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        // Overlay events are ours too. MainActivity explicitly clears this state
        // on resume, without relying on hidden View/window-id APIs.
        if (overlay != null && pkg == packageName) return
        val inputs = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        if (inputs.enabledInputMethodList.any { it.packageName == pkg }) return
        val home = packageManager.resolveActivity(android.content.Intent(android.content.Intent.ACTION_MAIN).addCategory(android.content.Intent.CATEGORY_HOME), 0)?.activityInfo?.packageName
        source = if (pkg == packageName || pkg == home || pkg in protectedPackages) null else "android:$pkg"
        if (source != blocked) hideBlock()
    }

    fun enteredLockin() {
        source = null
        hideBlock()
        TrackingRuntime.dismissRequested()
    }

    fun foregroundSource(): String? {
        if (!TrackingRuntime.enabled(this)) { source = null; hideBlock(); return null }
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (!power.isInteractive || keyguard.isKeyguardLocked) { source = null; hideBlock(); return null }
        return source
    }

    fun showBlock(target: String, message: String) {
        require(target.startsWith("android:")) { "Only Android apps can be blocked here." }
        val pkg = target.removePrefix("android:")
        if (pkg == packageName || pkg in protectedPackages || foregroundSource() != target) return
        if (overlay != null && blocked == target) return
        hideBlock()
        val density = resources.displayMetrics.density
        val padding = (24 * density).toInt()
        val font = try { Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/Inter.ttf") } catch (_: Exception) { Typeface.DEFAULT }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(padding, padding, padding, padding)
            setBackgroundColor(Color.rgb(9, 9, 10))
        }
        fun text(value: String, size: Float) = TextView(this).apply {
            text = value; textSize = size; setTextColor(Color.WHITE); typeface = font
            gravity = Gravity.CENTER; setPadding(0, padding / 2, 0, padding / 2)
        }
        content.addView(text("App restricted", 26f))
        content.addView(text(message, 16f))
        content.addView(Button(this).apply {
            text = "Go home"; typeface = font
            setOnClickListener { hideBlock(); source = null; TrackingRuntime.dismissRequested(); performGlobalAction(GLOBAL_ACTION_HOME) }
        })
        content.addView(Button(this).apply {
            text = "Allow this app for 5 minutes"; typeface = font
            setOnClickListener { TrackingRuntime.overrideRequested() }
        })
        content.addView(text("Tracking stays on. Other restrictions remain active.", 13f))
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.OPAQUE,
        )
        overlayWindows.addView(content, params)
        blocked = target
        overlay = content
    }

    fun hideBlock() {
        overlay?.let { overlayWindows.removeView(it) }
        overlay = null
        blocked = null
    }

    override fun onInterrupt() { source = null; hideBlock() }
    override fun onDestroy() { hideBlock(); instance = null; super.onDestroy() }

    companion object {
        @Volatile var instance: AppBlockingService? = null
            private set
    }
}
