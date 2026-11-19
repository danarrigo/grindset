package app.lockin.lockin

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

/**
 * Play Store edition only. Notes which app came to the front and asks for a
 * rule check at once, instead of waiting for the next one-second check and for
 * usage history to catch up. Only the event's package name is used; window
 * content is never read.
 */
class InstantBlockingService : AccessibilityService() {
    override fun onServiceConnected() {
        AppBlocker.instantConnected = true
    }

    override fun onUnbind(intent: Intent?): Boolean {
        AppBlocker.instantConnected = false
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        AppBlocker.instantConnected = false
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        // Grindset's own block screen must not trigger another check.
        if (pkg == packageName) return
        AppBlocker.noteForeground(this, pkg)
        TrackingRuntime.foregroundChanged()
    }

    override fun onInterrupt() = Unit
}
