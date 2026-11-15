# Budget warnings

Enable **Settings > Budget warnings** for a heads-up when confirmed usage reaches 80% of an activity's daily shared budget, while it is still below the limit. This is off by default, requires tracking to be on, and does not enable tracking, change limits, pause timers or weaken blocking. Focus profiles and scheduled restrictions are unaffected.

Warnings appear in Focus and Rules. Windows/Android also request an immediate system notification where permitted, independently of completion alerts. Android budget warnings request notification permission only, not exact-alarm permission. A denied/failed OS request leaves the on-screen warning available. Acceptance of the notification request is not proof of visible delivery.

Each activity is warned once per account-timezone day, persisted across restart. Editing its budget or toggling warnings does not repeatedly notify on that same day. Simultaneous new warnings are summarized in one notification; the in-app view shows the individual activities. Failed requests are not retried on every collector tick. Disabling warnings stops new requests; existing notifications may remain in the OS notification center. No deadline is pre-scheduled from estimated future activity.

Calculations union overlapping app/site/device observations and use current budgets plus recorded/synced usage. Offline devices may have consumed more than is known locally. A jump from below 80% to an already reached limit does not produce a misleading late pre-limit warning. Native previews using `--no-alerts` show on-screen warnings only. Physical Android and visible Windows notification delivery remain separate acceptance boundaries.
