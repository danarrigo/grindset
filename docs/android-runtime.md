# Android background runtime

Tracking is opt-in. Enable Usage Access and notifications in Settings. Lockin starts a `specialUse` foreground service with a persistent notification and a stop action. Force-stop, system termination, uninstall and permission revocation can still interrupt it. The foreground-service declaration and Accessibility use require policy review before Play distribution.

## Ownership

`TrackingRuntime.kt` retains one Flutter engine shared by `MainActivity` and `TrackingService`. Closing the activity does not destroy a tracking engine. The same Dart controller, SQLite database and Supabase auth client continue running; there is no second database, duplicate auth refresh client or separate native copy of the restriction policy.

Every 15 seconds the controller commits OS-confirmed usage intervals and its import checkpoint in one SQLite transaction. Queries overlap to repair delayed OS events. Interval identity uses the original resume timestamp, clamped to the current collection window rather than the query/day boundary. After an interruption, bounded backfill uses Android's retained history; unavailable history is not invented. Screen-off/keyguard events close intervals, and a locked screen cannot extend a stale open interval.

The notification's stop choice is authoritative in native preferences. The Dart database adopts it even when the stop callback was lost. Boot/package-replacement restart occurs only after opt-in and with required permissions; failures are shown rather than silently treated as running.

Usage Access, app-wide notifications, and the tracking notification channel must remain enabled. The native service checks them at startup and once per second, independently of a busy Dart import. Losing a requirement pauses the service and persists an actionable reason without discarding the opt-in. Opening Lockin after restoring access starts a new collection window. Neither permission-disabled gaps nor explicitly stopped periods are backfilled. Ordinary process/reboot recovery retains the existing window while permissions remain valid. In-flight reads are rejected if permissions or the collection generation change before delivery. A legacy installation without a recorded window starts one conservatively; it does not reconstruct pre-upgrade consent.

## Optional blocking

Enable **Lockin app blocking** yourself in Android Accessibility settings, after the in-app disclosure. The service requests only window-state events and reads package identifiers. It does not retrieve a window content tree, text, screenshots, keystrokes or gestures.

The existing Dart policy evaluates focus blocks, union-accounted daily budgets and account-timezone schedules. An active restriction displays a native accessibility overlay. A five-minute override is committed for one source on this device before the overlay is dismissed. Android Settings, the launcher, permission/install interfaces and Lockin remain accessible. This is voluntary enforcement, not tamper or uninstall protection.

## Verification status

Controller/SQLite tests cover repeated imports, checkpoint failure, native stop authority, policy decisions, source-specific overrides, interruption reasons surviving refresh/reopen, and requesting only missing Usage Access. Those tests mock the OS boundary.

The debug APK was installed on the isolated API 36.1 emulator. Actual UI checks verified Usage Access and notification consent, the visible foreground service, journal writes after closing/reopening the activity, a native focus-blocking overlay, a persisted source-specific override, and stopping tracking from the real notification. A screen-off check confirmed the Chrome interval ended at 12:33:12.739 UTC while the next import completed at 12:33:29.103 UTC, without adding the locked interval. Accessibility reported package-only window events with capabilities=0. This is emulator evidence, not physical-device or store approval.

Do not use `uiautomator dump` to verify a live Accessibility overlay: its UiAutomation connection suppresses other accessibility services during the dump. Use the real screen and OS diagnostics instead.

Completion-alert delivery with tracking disabled, the UI closed and the background process killed is now emulator-verified. See [completion alerts](completion-alerts.md) for exact evidence and limits. The retained `b2bc284` APK was hash-matched before additional recovery checks. Killing its process restarted the foreground service without reopening Lockin and advanced its import checkpoint from 10:28:47.204023 UTC to 10:29:11.232884 UTC on 2026-11-12. A real emulator reboot then restored collection, advancing the checkpoint from 10:30:41.252635 UTC to 10:32:56.026560 UTC without extending the old Chrome interval through screen-off/reboot. These are bounded emulator results on the pre-permission-fix binary.

The same binary exposed a real bug: revoking `POST_NOTIFICATIONS` left its foreground service running and advanced its checkpoint from 10:38:19.551565 UTC to 10:38:54.901559 UTC. The native guards/window changes above address that path, but new-binary validation is still pending. Run `python3 test/native/android_tracking_permissions_test.py /path/to/adb.exe` against the already opted-in dedicated `Lockin_Test_API_36_1` fixture. The script checks notification and Usage Access revocation, persistent reasons, restoration, and empty denied gaps. It changes only that fixture's Lockin permissions and restores them afterward; it does not establish onboarding UI behavior.

Notification-channel-only revocation, OEM battery management and physical-device validation remain outstanding. Do not advertise uninterrupted or store-approved enforcement.
