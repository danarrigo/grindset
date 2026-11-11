# Lockin

A local-first focus app for **Windows + Android**, built with Flutter/Dart. The approved full v1 scope is in [docs/v1-spec.md](docs/v1-spec.md).

**This is an implementation checkpoint, not the completed v1.** The interface deliberately labels unfinished integrations. There is no fabricated usage or pretend live-device data.

![Desktop UI rendered by the widget test](test/goldens/desktop.png)

Widget-rendered previews of the real app: [desktop](test/goldens/desktop.png) · [mobile](test/goldens/mobile.png) · [menu](test/goldens/mobile-menu.png) · [active focus](test/goldens/mobile-focus.png) · [break](test/goldens/mobile-break.png) · [completed](test/goldens/mobile-complete.png) · [maximized](test/goldens/desktop-wide.png).

The approved Focus design is just the time, one start/end control and a small menu. Duration, phase selection and navigation live in the menu; focused time is in Activity and individual budgets are in Rules. Focus stays dark in either system appearance, while secondary screens follow the system theme. The [throwaway comparison](https://github.com/danarrigo/lockin/tree/design/apple-focus-prototype/lib/ui/focus_prototype) remains separate from the production app.

## What is here

| Area | Current state |
| --- | --- |
| Interface | Approved minimal Focus screen wired to real state; immediate Lock in action; compact Windows utility window; matching phone layout; licensed Inter and Cupertino Icons |
| Timers | Pomodoro/custom durations, manual phase starts, deadline-based restoration, shared active session and union-accounted focus history |
| Accounting | Cross-device interval union, account-timezone days, daylight-saving boundaries, per-device totals |
| Rules | Shared activity rules, daily budgets and schedules; device-local focus blocklists and source-specific five-minute overrides; explicit offline conflict review |
| Storage | SQLite through Drift; durable intervals, settings and session history; safe upload acknowledgements |
| Windows | Win32 foreground reader, tray/close-to-tray, sign-in startup, idle/audio/media probe, voluntary focus interruption; native behavior **not yet device-tested** |
| Android | Opt-in foreground service keeps one cached Flutter engine and SQLite usage journal alive after UI close; optional package-only Accessibility blocker; native validation in progress |
| Browsers | Paired Chrome/Edge extension, host-only foreground heartbeats, website rules and per-site overrides; loopback/policy-tested, **not yet browser/device-tested** |
| Supabase | Automatic usage/account-state sync with durable outbox, retries, idempotent acknowledgements and owner-scoped revisions; HTTP and PostgreSQL/RLS-tested, **not live-deployed** |

### Still required for the approved v1

- Native validation of Android background collection and Accessibility blocking across UI close, reboot, lock, permission loss and OS termination. These paths are now implemented but are not yet release-verified. See [Android runtime](docs/android-runtime.md).
- Live Supabase deployment and two-device validation of shared sessions, rules, timezone and offline reconciliation. The implementation and conflict-review UI are now present. See [shared sync](docs/shared-sync.md).
- Native/browser validation of the Windows idle/media probe and paired Chrome/Edge integration. See [browser integration](docs/browser-extension.md).
- Windows crash/restart recovery and persistent tracking interruption reporting.
- Completion notifications, native end-to-end tests, signed packaging, and release/privacy review.

No claim of continuous background enforcement is justified until these paths pass physical-device and Windows tests. Force-stop, permission revocation, uninstalling and OS restrictions can still stop a consumer app.

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

1. In your own Supabase project, apply both files in [supabase/migrations/](supabase/migrations/) in filename order, using the Supabase CLI or SQL editor.
2. Copy `config.example.json` to `config.local.json` and fill in your project URL and **public publishable key**. An older public anon key also works. Never use a service-role key.
3. Run `flutter run -d windows --dart-define-from-file=config.local.json` (or choose your Android device).
4. In Settings, create/confirm an account and sign in on each device. Account state and confirmed usage then synchronize automatically; **Sync now** retries immediately. Email confirmation/delivery settings belong to your Supabase project.

Usage sync uploads confirmed intervals idempotently and downloads today's data with explicit pagination. It does not extrapolate offline device activity. Device heartbeats are labelled **last contacted**, not proof of fresh activity. Global budgets can overshoot while disconnected. Shared rules, timezone, the active session and timer history synchronize through a revisioned outbox. Confirmed policy wins stale edits; Settings retains conflicting rule/timezone edits for explicit review. Focus blocklists and overrides stay device-local. Sync runs every 30 seconds with prompt requests after local changes and retry backoff. Android background operation requires its visible foreground service.

Local history is bound to its first cloud account. Uploading it to a different account is refused; a safe account-switch/reset flow is still pending.

## Verification

- `flutter analyze` checks the Dart/Flutter code.
- `flutter test` exercises public timer/editor flows, actual SQLite close/reopen behavior, interval union, schedules, DST, override expiry and upload races.
- App-level widget tests cover immediate starts, deadline accuracy, real SQLite session restoration, immediately saved, independently remembered focus/break durations, manual phases, navigation during a timer, individual union-accounted budgets, and the blocking/override UI. They also cover keyboard-open forms, a 320-pixel short screen with doubled text and a warning, contrast, labeled controls and mobile tap targets. Idle, menu, running, break and completion goldens are generated by `flutter test --update-goldens`; inspect changes before accepting them.
- Browser bridge tests use actual loopback HTTP and the controller/SQLite journal to verify pairing, host-only payloads, stale observations, native-foreground matching and disabled-gap accounting. Extension policy tests cover domain matching and override priority. Windows idle/media tests mock the OS channel; actual native/browser validation is still required.
- Android bridge tests exercise the real controller/store against a mocked OS method channel. Sync tests use a local HTTP server to exercise the actual Supabase client, pagination, retries, overlapping uploads and account binding. These do not prove Android OS behavior or server-side RLS.
- Shared-state tests cover two independent device databases, timer completion, focus-blocklist scope, revision pagination, conflicting edits, upload races, schema-one migration and durable outbox restoration. PostgreSQL 16 runs the actual migrations and tests the RPC and two-user RLS using a fixture Auth boundary. This does not replace testing a deployed Supabase project.
- Native Android/Windows builds and database checks run in [GitHub Actions](.github/workflows/verify.yml), which publishes short-lived debug APK and unsigned Windows artifacts. Build success is not device-level enforcement verification.

## Privacy and licensing

Cloud usage records contain app/domain identifiers and timestamps, never window titles, full URLs, screenshots, keystrokes or executable paths. Android automatic app-data backup is disabled. Local database/configuration files are ignored by git. Each cloud row is scoped to its authenticated owner.

Inter is bundled under its [SIL Open Font License](assets/fonts/OFL.txt). Symbols use the licensed Flutter Cupertino Icons package, not a proprietary Apple font.
