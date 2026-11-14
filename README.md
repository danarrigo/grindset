# Grindset

A local-first focus app for **Windows + Android**, built with Flutter/Dart. The approved full v1 scope is in [docs/v1-spec.md](docs/v1-spec.md).

**v1.2.0 is a personal-use release with known limitations, not physical-device certification or store-reviewed distribution.** The interface deliberately labels experimental integrations. There is no fabricated usage or pretend live-device data.

Download the Windows installer, stable-key Android ARM64 APK and browser extension from [Releases](https://github.com/danarrigo/grindset-releases/releases). See the [release notes](docs/releases/v1.2.0.md) for installation and limitations. Existing app/package IDs, executable/storage identifiers and signing keys remain unchanged for compatibility with the former Lockin name.

![Desktop UI rendered by the widget test](test/goldens/desktop.png)

Widget-rendered previews of the real app: [desktop](test/goldens/desktop.png) · [mobile](test/goldens/mobile.png) · [menu](test/goldens/mobile-menu.png) · [active focus](test/goldens/mobile-focus.png) · [break](test/goldens/mobile-break.png) · [completed](test/goldens/mobile-complete.png) · [maximized](test/goldens/desktop-wide.png).

The approved Focus design is just the time, one start/end control and a small menu. Duration, phase selection and navigation live in the menu; focused time is in Activity and individual budgets are in Rules. Focus stays dark in either system appearance, while secondary screens follow the system theme. The [throwaway comparison](https://github.com/danarrigo/grindset/tree/design/apple-focus-prototype/lib/ui/focus_prototype) remains separate from the production app.

## What is here

| Area | Current state |
| --- | --- |
| Interface | Approved minimal Focus screen wired to real state; immediate Lock in action; compact Windows utility window; matching phone layout; licensed Inter and Cupertino Icons |
| Timers | Pomodoro/custom durations, manual phase starts, deadline-based restoration, shared active session and union-accounted focus history |
| Accounting | Cross-device interval union, account-timezone days, daylight-saving boundaries, per-device totals |
| Rules | Nine editable starter activities with ready-made website/Android identifiers; shared daily budgets and schedules; device-local focus blocks and five-minute overrides; explicit offline conflict review |
| Storage | SQLite through Drift; private JSON export, explicit device-local reset/account switching, durable outbox/history and safe upload acknowledgements |
| Windows | Win32 foreground reader, tray/close-to-tray, preview startup isolation, interruption notices and installer; Chrome foreground idle/video checks pass, desktop-player/lock checks remain |
| Android | Opt-in foreground service keeps one cached Flutter engine and SQLite usage journal alive after UI close; optional package-only Accessibility blocker; native validation in progress |
| Browsers | Actual Chrome/Edge blocking and overrides pass; Chrome website accounting and idle/video checks pass; Edge foreground accounting and manual browser onboarding remain |
| Supabase | Inbox confirmation and installed Windows/Android-emulator login, timezone/session/rule/budget/usage sync verified; hosted RLS/offline recovery verified separately; confirmation redirect still needs fixing |

### Known limitations and deferred acceptance

- Physical Android/OEM validation, Android post-reset redownload. Export/document-picker, local reset and the patched identifier-entry form now pass on the emulator. Background collection, process/reboot recovery, permission loss, lock boundaries, blocking and completion delivery still have bounded emulator evidence, not physical-device certification. See [Android runtime](docs/android-runtime.md).
- The app-owned [confirmation page](https://danarrigo.github.io/grindset-releases/confirmed/) is deployed, and signup/resend explicitly request it. The hosted Auth Site URL still needs its dashboard change from localhost; the available MCP OAuth permission cannot change Auth configuration. Inbox confirmation, native Windows/Android-emulator password login and shared timezone/timer/history/rules/budgets/usage now pass. Installed offline-conflict flows remain separate from the hosted-client recovery checks. See [deployment evidence](docs/supabase-deployment.md) and [shared sync](docs/shared-sync.md).
- Native Edge foreground accounting, Windows desktop-player media and screen-lock boundaries, and manual extension onboarding. Actual restriction pages and five-minute overrides now pass in both Chrome and Edge; Chrome's real foreground website accounting and idle/video behavior also pass. The rebuilt preview also tracks without changing startup or triggering a new Defender detection with real-time protection on. See [packaging](docs/packaging.md) and [browser integration](docs/browser-extension.md).
- Windows interruption restart/dismissal acceptance and visible completion-notification delivery. The native interruption notice and its persisted journal state are verified, without invented usage in the observed gap. Native early-end and alerts-off cancellation now pass against the actual OS schedule; Windows export/reset passed on an isolated local-mode preview and installer smoke checks passed in CI. See [completion alerts](docs/completion-alerts.md) and [data controls](docs/data-controls.md).
- Public distribution still needs separate privacy/policy review; no Windows trust certificate has been purchased. The Android signing backup is now encrypted in Google Drive and recovery-verified, with the passphrase held separately by the owner. See [packaging](docs/packaging.md).

No claim of continuous background enforcement is justified until these paths pass physical-device and Windows tests. Force-stop, permission revocation, uninstalling and OS restrictions can still stop a consumer app.

## Updates

Install v1.2.0 manually once to gain **Settings > App updates > Check for updates**. Checks are explicit, show release notes and open the platform's public download in your browser. Run the Windows installer or approve Android's APK update over the existing release. This is not silent/background installation. Source stays private; the [public distribution repository](https://github.com/danarrigo/grindset-releases) contains only the website, feed and release files. See [update behavior](docs/app-updates.md).

## Starter activities

Open **Rules** and choose Instagram, YouTube, TikTok, Reddit, X, Facebook, Snapchat, Twitch or Discord. Review the prefilled website/Android sources, suggested **30-minute daily limit** and **Block during focus**, then save. Nothing is added automatically, existing rules are preserved, and tracking/permissions remain opt-in. See [starter behavior and coverage](docs/rule-presets.md).

## Development

Use **Flutter stable 3.47.9 / Dart 3.13.7** to reproduce the checked-in UI goldens. The session's persistent WSL SDK is `~/.local/share/lockin/flutter`. To use it in the current shell, run `export PATH="$HOME/.local/share/lockin/flutter/bin:$PATH"`. Windows builds require a separate Windows-side Flutter installation.

```sh
flutter pub get
flutter analyze
flutter test
node --test extension/*.test.js
```

Run on Windows with `flutter run -d windows`, or on an attached Android device with `flutter run -d <device-id>`.

### Windows and WSL

Editing in WSL/Neovim is fine. Windows builds require **Windows-side Flutter** and Visual Studio 2022's **Desktop development with C++** workload; Linux Flutter cannot build the Windows executable. Enable Windows Developer Mode for plugin symlinks. Android builds need the Java/Android SDK toolchain in the environment running Flutter, plus a device/emulator for end-to-end validation. Windows Android Studio's `.exe` tools are not a Linux Android toolchain.

The compatible `win32` 5.x / desktop-plugin dependency family is intentional: `launch_at_startup` currently depends on the 5.x registry bindings. Upgrade these together and revalidate native behavior, rather than forcing incompatible major versions.

### Supabase (optional; local mode needs no credentials)

1. For a new project, apply all files in [supabase/migrations/](supabase/migrations/) in filename order, using the Supabase CLI or SQL editor. This repository's project is already deployed; check [migration history](docs/supabase-deployment.md) before replaying anything.
2. Copy `config.example.json` to `config.local.json` and fill in your project URL and **public publishable key**. An older public anon key also works. Never use a service-role key.
3. Run `flutter run -d windows --dart-define-from-file=config.local.json` (or choose your Android device).
4. In Settings, create/confirm an account and sign in on each device. Account state and confirmed usage then synchronize automatically; **Sync now** retries immediately. Email confirmation/delivery settings belong to your Supabase project.

Usage sync uploads confirmed intervals idempotently and downloads today's data with explicit pagination. It does not extrapolate offline device activity. Device heartbeats are labelled **last contacted**, not proof of fresh activity. Global budgets can overshoot while disconnected. Shared rules, timezone, the active session and timer history synchronize through a revisioned outbox. Confirmed policy wins stale edits; Settings retains conflicting rule/timezone edits for explicit review. Focus blocklists and overrides stay device-local. Sync runs every 30 seconds with prompt requests after local changes and retry backoff. Android background operation requires its visible foreground service.

Local history is bound to its first cloud account. Uploading it to a different account is refused. Settings provides **Export data** and **Reset this device**: reset stops collectors/alerts, drains sync, signs out locally, clears this device's history/account link and closes the app. Cloud records remain untouched. Reopen before using another account. See [device data controls](docs/data-controls.md).

Push/PR CI Android APKs are debug previews, not stable release-signed installers. GitHub release APKs are built separately with the retained owner signing key. Their signing key can change between runner images, preventing an in-place upgrade. Do not uninstall a personal installation merely to upgrade without preserving its data. Stable-key Android release configuration and a per-user Windows installer are implemented; actual signing credentials remain owner-controlled. See [packaging and update behavior](docs/packaging.md).

## Completion notifications

Enable **Completion notifications** in Settings. Alerts are independent of activity tracking and use the OS scheduler, so closing the UI does not require a second tracking service. An early finish, a changed shared session, or disabling alerts cancels the previous deadline. Phases still start manually. Android asks for notification and exact-alarm permission; without exact-alarm permission it schedules an inexact alert and reports that delivery may be delayed. Windows uses toast notifications. OS notification settings, battery restrictions and force-stop can suppress delivery. Android delivery after UI close and process death is emulator-verified; Windows OS scheduling and native early-end/alerts-off cancellation are verified, but visual delivery and physical-device behavior still need checks. See [completion-alert evidence](docs/completion-alerts.md).

Notifications use the maintained 23.x plugin with Android compile SDK 37 and AGP 9.1.1. The older Windows implementation failed on current MSVC; upgrading avoids patching generated/vendor sources. The app's target SDK still follows Flutter's target. Do not suppress permission failures or label an alert delivered merely because scheduling returned successfully.

## Verification

- `flutter analyze` checks the Dart/Flutter code.
- `flutter test` exercises public timer/editor flows, actual SQLite close/reopen behavior, interval union, schedules, DST, override expiry and upload races.
- App-level widget tests cover immediate starts, deadline accuracy, real SQLite session restoration, immediately saved, independently remembered focus/break durations, manual phases, navigation during a timer, individual union-accounted budgets, and the blocking/override UI. They also cover keyboard-open forms, a 320-pixel short screen with doubled text and a warning, contrast, labeled controls and mobile tap targets. Idle, menu, running, break and completion goldens are generated by `flutter test --update-goldens`; inspect changes before accepting them.
- Browser bridge tests use actual loopback HTTP and the controller/SQLite journal to verify pairing, host-only payloads, stale observations, native-foreground matching and disabled-gap accounting. Extension policy tests cover domain matching and override priority. Actual Chrome/native checks found and fixed privileged GET origin handling and verified blocking, overrides and eventual disconnect recovery. Windows idle/media tests still mock the OS channel; see [native browser evidence and remaining checks](docs/browser-extension.md).
- Android bridge tests exercise the real controller/store against a mocked OS method channel. Sync tests use a local HTTP server to exercise the actual Supabase client, pagination, retries, overlapping uploads and account binding. These do not prove Android OS behavior or server-side RLS.
- Completion tests exercise the actual controller and notification SDK at a mocked OS channel: opt-in, UTC deadlines rounded up (never early), early cancellation, disabled/denied permissions, delayed fallback, shared-session changes, restart restoration, retries and in-flight scheduling races. These do not prove OS delivery.
- Shared-state tests cover two independent device databases, timer completion, focus-blocklist scope, revision pagination, conflicting edits, upload races, schema-one migration and durable outbox restoration. PostgreSQL 16 runs the actual migrations and tests the RPC and two-user RLS using a fixture Auth boundary. The opt-in `test/live_cloud_sync_test.dart` separately passed against deployed Supabase with real Auth and independent journals; see [setup and evidence limits](docs/supabase-deployment.md).
- Native Android/Windows builds and database checks run in [GitHub Actions](.github/workflows/verify.yml), which publishes short-lived per-ABI debug APKs and unsigned Windows artifacts. Use the ARM64 APK for a compatible phone and x64 for the test emulator; separate artifacts avoid downloading both engines. Build success is not device-level enforcement verification.

## Privacy and licensing

Cloud usage records contain app/domain identifiers and timestamps, never window titles, full URLs, screenshots, keystrokes or executable paths. Android automatic app-data backup is disabled. Local database/configuration files are ignored by git. Each cloud row is scoped to its authenticated owner.

Inter is bundled under its [SIL Open Font License](assets/fonts/OFL.txt). Symbols use the licensed Flutter Cupertino Icons package, not a proprietary Apple font.
