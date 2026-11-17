# Android background runtime

Tracking is opt-in. Enable Usage Access and notifications in Settings. Grindset starts a `specialUse` foreground service with a persistent notification and a stop action. Force-stop, system termination, uninstall and permission revocation can still interrupt it. The foreground-service declaration and overlay permission require policy review before Play distribution.

## Ownership

`TrackingRuntime.kt` retains one Flutter engine shared by `MainActivity` and `TrackingService`. Closing the activity does not destroy a tracking engine. The same Dart controller, SQLite database and Supabase auth client continue running; there is no second database, duplicate auth refresh client or separate native copy of the restriction policy.

Every 15 seconds the controller commits OS-confirmed usage intervals and its import checkpoint in one SQLite transaction. Queries overlap to repair delayed OS events. Interval identity uses the original resume timestamp, clamped to the current collection window rather than the query/day boundary. After an interruption, bounded backfill uses Android's retained history; unavailable history is not invented. Screen-off/keyguard events close intervals, and a locked screen cannot extend a stale open interval.

The notification's stop choice is authoritative in native preferences. The Dart database adopts it even when the stop callback was lost. Boot/package-replacement restart occurs only after opt-in and with required permissions; failures are shown rather than silently treated as running.

Usage Access, app-wide notifications, and the tracking notification channel must remain enabled. The native service checks them at startup and once per second, independently of a busy Dart import. Losing a requirement pauses the service and persists an actionable reason without discarding the opt-in. Opening Grindset after restoring access starts a new collection window. Neither permission-disabled gaps nor explicitly stopped periods are backfilled. Ordinary process/reboot recovery retains the existing window while permissions remain valid. In-flight reads are rejected if permissions or the collection generation change before delivery. A legacy installation without a recorded window starts one conservatively; it does not reconstruct pre-upgrade consent.

## Optional blocking

After the in-app disclosure, allow Grindset to **Display over other apps** yourself in Android Settings. While tracking runs, Grindset reads the latest foreground activity's package identifier from Usage Access events about once a second. It does not read screen contents, text, screenshots, keystrokes or gestures. Because detection is polled, a restricted app can be visible for up to about a second before the restriction screen covers it.

Grindset does not declare an Accessibility service. Google's sideloading fraud protection blocks internet-downloaded APKs that declare one ("This app can request access to sensitive data"), even when the service is never enabled. v1.5 and earlier v1.6 builds declared it.

The existing Dart policy evaluates focus blocks, union-accounted daily budgets and account-timezone schedules. An active restriction displays a native full-screen overlay window above the app. System bars stay usable. A five-minute override is committed for one source on this device before the overlay is dismissed. Android Settings, the launcher, permission/install interfaces and Grindset remain accessible. This is voluntary enforcement, not tamper or uninstall protection.

## Verification status

Controller/SQLite tests cover repeated imports, checkpoint failure, native stop authority, policy decisions, source-specific overrides, interruption reasons surviving refresh/reopen, and requesting only missing Usage Access. Those tests mock the OS boundary.

The debug APK was installed on the isolated API 36.1 emulator. Actual UI checks verified Usage Access and notification consent, the visible foreground service, journal writes after closing/reopening the activity, a native focus-blocking overlay, a persisted source-specific override, and stopping tracking from the real notification. A screen-off check confirmed the Chrome interval ended at 12:33:12.739 UTC while the next import completed at 12:33:29.103 UTC, without adding the locked interval. Accessibility reported package-only window events with capabilities=0. This is emulator evidence, not physical-device or store approval.

Completion-alert delivery with tracking disabled, the UI closed and the background process killed is emulator-verified. See [completion alerts](completion-alerts.md) for exact evidence and limits.

A hash-matched `b2bc284` APK exposed the permission-loss bug: revoking `POST_NOTIFICATIONS` left its foreground service running and advanced its checkpoint from 10:38:19.551565 UTC to 10:38:54.901559 UTC on 2026-11-12. The retained regression script also failed against that binary across two separate denied-state samples, ruling out only an old in-flight import.

The patched `a5ec8ea` APK from successful CI run `43234510856` was then installed only on the dedicated API 36.1 AVD. Its SHA-256 was `ca2875bf2954665d8e4d44d598f4da0836b0328cc616ba22f80fadfaf1d441db`. Actual OS checks on 2026-11-12 verified:

- Notification revocation stopped the foreground collector. Both post-denial samples retained checkpoint 14:32:27.582554 UTC and the native interruption reason.
- Usage Access revocation likewise stopped collection and retained checkpoint 14:33:31.461602 UTC across both samples.
- Restoring each permission resumed imports, cleared the reason, and left no Android intervals overlapping the denied window.
- Process death restarted the collector without reopening Lockin, advancing the checkpoint from 14:36:01.470225 UTC to 14:36:32.617711 UTC while preserving the permitted collection window/generation.
- A real reboot preserved that window/generation and resumed imports without opening Lockin. The checkpoint advanced from 14:43:11.486461 UTC to 14:45:26.242536 UTC without extending the old Chrome interval through screen-off/reboot. The post-unlock checkpoint was observed after 71.9 seconds; an initial fixed 22-second wait was insufficient. This is not an immediate-recovery guarantee.

Run `python3 test/native/android_tracking_permissions_test.py /path/to/adb.exe --serial emulator-5554` against the already opted-in dedicated `Lockin_Test_API_36_1` fixture, substituting its current ADB serial. The script checks app-wide notification permission, tracking-channel-only and Usage Access revocation, persistent reasons, restoration, and empty denied gaps. It checks the AVD name before modifying permissions, including under Python's `-O` mode. It changes only that fixture's Lockin permissions and restores them afterward; it does not establish onboarding UI behavior. These permission fixtures and emulator results do not establish physical-device behavior.

### Tracking-channel-only acceptance (2026-11-13)

The retained script passed all three cases on the same hash-verified `a5ec8ea` API 36.1 fixture. The channel-only case used Android's real channel Settings switch, not app-wide notification revocation. Collection stopped, preserved the opt-in, closed its collection window and retained **Allow the background activity tracking notification channel.** Both denied-state samples kept checkpoint `2026-11-13T05:06:30.542717Z`. Restoring the channel and reopening Lockin resumed imports without intervals overlapping the denied window; `POST_NOTIFICATIONS` remained granted. The script restored all permissions/channel settings afterward.

The script previously hard-coded `emulator-5556`, failing when the fixture booted on `emulator-5554`; the explicit `--serial` argument fixes that test-runner defect without weakening fixture isolation. UiAutomation inspects only Android Settings for this test, not a live blocking overlay.

This does not validate the latest APK: installing CI run `43363379837` over the fixture was refused by Android because its debug signing key differed. The existing fixture was preserved, not uninstalled or reset. A later run archived that known, cloud-unbound fixture before installing `14b597f` freshly. Its real Android export/document-picker and local reset paths then passed; see [data controls](data-controls.md). The reset left all six local tables empty before another fresh install of `3a312e4`, whose keyboard-source fix passed CI. A subsequent essential check hash-matched the installed APK to that artifact and used the real Android form/IME to enter `Android:com.android.chrome,Web:Example.ORG`. Saving succeeded; an independent SQLite snapshot contained exactly `android:com.android.chrome` and `web:example.org`. The active editor input type was `0xa0091`, with suggestions/autocorrection disabled. This closes the native input-fix retest, not physical-device reliability. The emulator was shut down with that fresh installation's tracking off. Rerunning the permission script requires explicit opt-in and permissions on the current fixture first; older fixture evidence does not certify the new binary. OEM battery management and physical-device validation remain outstanding. Do not advertise uninterrupted or store-approved enforcement.
