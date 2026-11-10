package app.lockin.lockin

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import android.os.Process

object UsageReader {
    fun hasAccess(context: Context): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= 36 || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        } else {
            // Correct compatibility path for Android 10-15; superseded in API 36.
            @Suppress("DEPRECATION")
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    // Android records this history even when the Flutter activity is closed.
    // Retention is controlled by Android; this is not a permanent background journal.
    fun read(context: Context, from: Long, requestedUntil: Long): List<Map<String, Any>> {
        check(hasAccess(context)) { "Enable Usage Access in Android Settings first" }
        val until = minOf(requestedUntil, System.currentTimeMillis())
        if (from >= until) return emptyList()
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        // Seed foreground state before the requested window, without guessing.
        val events = manager.queryEvents(maxOf(0L, from - 86_400_000L), until)
            ?: return emptyList()
        val event = UsageEvents.Event()
        val records = mutableListOf<Map<String, Any>>()
        var foreground: String? = null
        var began = from
        var unlocked = true
        fun close(at: Long) {
            val pkg = foreground
            val start = maxOf(began, from)
            val end = minOf(at, until)
            if (pkg != null && pkg != context.packageName &&
                pkg != "com.android.systemui" && end > start) {
                records.add(mapOf("source" to "android:$pkg", "start" to start, "end" to end))
            }
            foreground = null
        }
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    close(event.timeStamp)
                    if (unlocked) {
                        foreground = event.packageName
                        began = event.timeStamp
                    }
                }
                UsageEvents.Event.ACTIVITY_PAUSED -> {
                    if (event.packageName == foreground) close(event.timeStamp)
                }
                UsageEvents.Event.SCREEN_NON_INTERACTIVE, UsageEvents.Event.KEYGUARD_SHOWN -> {
                    close(event.timeStamp)
                    unlocked = false
                }
                UsageEvents.Event.SCREEN_INTERACTIVE, UsageEvents.Event.KEYGUARD_HIDDEN -> unlocked = true
                UsageEvents.Event.DEVICE_SHUTDOWN -> close(event.timeStamp)
            }
        }
        close(until)
        return records
    }
}
