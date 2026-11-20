# Focus hours

**Rules > Focus hours** sets times when every rule with **While I'm focusing** blocks, as if a focus session were running, with no timer. It is one schedule for the account, synced to all signed-in devices as the shared setting `focus_hours` (`{"schedules": [...]}`, validated like a rule's schedules, at most 64 windows; an empty list means off). Which rules block while focusing stays a per-device choice, as for focus sessions.

The block reason is **Focus hours**, and the Focus page shows "Focus hours until <time>" while no session runs. Times use the account timezone. An overnight window belongs to its starting weekday; boundaries are start-inclusive and end-exclusive.

Before v1.6.9, "Schedule focus hours" created an ordinary rule named Focus hours with its own apps and a schedule. Such rules keep working unchanged and can be edited or deleted like any rule.

Tracking and the relevant blocking integration must be enabled, as for any rule.

## v1.4.0 acceptance

Build `4c4af45`, CI `43647034313`, passed all five build/verification jobs. All 124 Flutter tests passed (one credential-dependent live test skipped), alongside analysis and extension/site tests. Tests cover multiple-window preservation, removal, invalid weekdays, overnight boundaries, named timezones, no-timer schedule enforcement, executable names with spaces, explicit discovery, browse cancellation/failure and existing-rule preservation. Desktop/mobile Rules goldens were reviewed and updated.

A real Windows portable preview used an isolated `--local-only --no-alerts` journal and an empty owned Windows Forms application. **Find apps on this PC** discovered it as running; filtering and checkbox selection saved its actual `windows:grindset-blocking-fixture.exe` identifier. No identifier was manually typed. The actual editor saved two time windows, selected Saturday and the account timezone America/Los_Angeles. A separate read-only Windows SQLite query confirmed the selected source, both windows, a null daily budget, a false manual-focus flag and no active session. After the real tracking disclosure was accepted, returning to the fixture minimized it and showed a 1920×1200 restriction screen explicitly labeled **Scheduled restriction**. No clock changes, fabricated sessions or cloud records were used.

Only the owned app window was captured. The preview and fixture were closed, local test tracking/alerts disabled, no linked cloud owner verified, and the normal startup entry verified unchanged. Evidence remains in the owned `grindset-v1.4-acceptance` temporary directory. The native file-dialog browse round trip was not repeated; its selection/cancel/error behavior is covered by widget tests, while native file-description metadata is shared with the exercised discovery path. Physical Android/OEM background reliability remains unverified.
