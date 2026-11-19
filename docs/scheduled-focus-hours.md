# Scheduled focus hours

In **Rules > Schedule focus hours**, choose the apps/websites to restrict, select weekdays and times, then save. This creates a normal editable activity named Focus hours. It starts with weekday 09:00-17:00, no daily budget and no timer-only focus blocking; nothing is saved or enabled automatically.

Schedules restrict the selected sources even when no timer is running. Use **Add time window** for split work periods, evenings or separate weekend hours. Editing preserves every existing window, budget and activity identity. At least one weekday and different start/end times are required for each window. Up to 64 windows are supported.

The editor and rule summary show the account timezone. An overnight window belongs to its starting weekday: Monday 22:00-02:00 includes early Tuesday. Boundaries are start-inclusive and end-exclusive; daylight-saving behavior follows the account's named timezone. Multiple windows combine as restrictions, not as additional timers. Overlapping rules still apply independently.

Tracking and the relevant blocking integration must be enabled. Windows needs Grindset running; website restrictions additionally need the paired browser extension. Android needs background tracking and the optional Display over other apps permission for app blocking. Quitting/turning tracking off stops enforcement; schedules do not create a service or bypass OS permissions. Physical Android background reliability remains a separate acceptance boundary.

Canceling the editor does not change rules. Turning off Scheduled focus hours and saving explicitly removes that activity's windows. Other activities remain unchanged.

## v1.4.0 acceptance

Build `4c4af45`, CI `43647034313`, passed all five build/verification jobs. All 124 Flutter tests passed (one credential-dependent live test skipped), alongside analysis and extension/site tests. Tests cover multiple-window preservation, removal, invalid weekdays, overnight boundaries, named timezones, no-timer schedule enforcement, executable names with spaces, explicit discovery, browse cancellation/failure and existing-rule preservation. Desktop/mobile Rules goldens were reviewed and updated.

A real Windows portable preview used an isolated `--local-only --no-alerts` journal and an empty owned Windows Forms application. **Find apps on this PC** discovered it as running; filtering and checkbox selection saved its actual `windows:grindset-blocking-fixture.exe` identifier. No identifier was manually typed. The actual editor saved two time windows, selected Saturday and the account timezone America/Los_Angeles. A separate read-only Windows SQLite query confirmed the selected source, both windows, a null daily budget, a false manual-focus flag and no active session. After the real tracking disclosure was accepted, returning to the fixture minimized it and showed a 1920×1200 restriction screen explicitly labeled **Scheduled restriction**. No clock changes, fabricated sessions or cloud records were used.

Only the owned app window was captured. The preview and fixture were closed, local test tracking/alerts disabled, no linked cloud owner verified, and the normal startup entry verified unchanged. Evidence remains in the owned `grindset-v1.4-acceptance` temporary directory. The native file-dialog browse round trip was not repeated; its selection/cancel/error behavior is covered by widget tests, while native file-description metadata is shared with the exercised discovery path. Physical Android/OEM background reliability remains unverified.
