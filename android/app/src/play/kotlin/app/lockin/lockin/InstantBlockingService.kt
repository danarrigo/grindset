package app.lockin.lockin

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

/**
 * Play Store edition only. Tells the rule check that another app came to the
 * front, so a blocked app is covered at once instead of at the next one-second
 * check. The usage history stays the source of truth for which app is open;
 * this only uses the event's package name and never reads window content.
 */
class InstantBlockingService : AccessibilityService() {
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        // Grindset's own block screen must not trigger another check.
        if (pkg == packageName) return
        TrackingRuntime.foregroundChanged()
    }

    override fun onInterrupt() = Unit
}
