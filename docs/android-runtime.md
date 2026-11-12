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

Completion-alert delivery with tracking disabled, the UI closed and the background process killed is emulator-verified. See [completion alerts](completion-alerts.md) for exact evidence and limits.

A hash-matched `b2bc284` APK exposed the permission-loss bug: revoking `POST_NOTIFICATIONS` left its foreground service running and advanced its checkpoint from 10:38:19.551565 UTC to 10:38:54.901559 UTC on 2026-11-12. The retained regression script also failed against that binary across two separate denied-state samples, ruling out only an old in-flight import.

The patched `a5ec8ea` APK from successful CI run `43234510856` was then installed only on the dedicated API 36.1 AVD. Its SHA-256 was `ca2875bf2954665d8e4d44d598f4da0836b0328cc616ba22f80fadfaf1d441db`. Actual OS checks on 2026-11-12 verified:

- Notification revocation stopped the foreground collector. Both post-denial samples retained checkpoint 14:32:27.582554 UTC and the native interruption reason.
- Usage Access revocation likewise stopped collection and retained checkpoint 14:33:31.461602 UTC across both samples.
- Restoring each permission resumed imports, cleared the reason, and left no Android intervals overlapping the denied window.
- Process death restarted the collector without reopening Lockin, advancing the checkpoint from 14:36:01.470225 UTC to 14:36:32.617711 UTC while preserving the permitted collection window/generation.
- A real reboot preserved that window/generation and resumed imports without opening Lockin. The checkpoint advanced from 14:43:11.486461 UTC to 14:45:26.242536 UTC without extending the old Chrome interval through screen-off/reboot. The post-unlock checkpoint was observed after 71.9 seconds; an initial fixed 22-second wait was insufficient. This is not an immediate-recovery guarantee.

Run `python3 test/native/android_tracking_permissions_test.py /path/to/adb.exe` against the already opted-in dedicated `Lockin_Test_API_36_1` fixture. The script checks notification and Usage Access revocation, persistent reasons, restoration, and empty denied gaps. It changes only that fixture's Lockin permissions and restores them afterward; it does not establish onboarding UI behavior. These permission fixtures and emulator results do not establish physical-device behavior.

Notification-channel-only revocation, OEM battery management and physical-device validation remain outstanding. Do not advertise uninterrupted or store-approved enforcement.
