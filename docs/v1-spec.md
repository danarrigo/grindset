# Lockin v1

Approved scope: a personal Windows + Android focus product, potentially commercial later. Flutter/Dart, Kotlin Android integrations, Win32 through Dart FFI, local SQLite/Drift, Supabase Auth/Postgres under the owner's account, and a Windows Chrome/Edge extension.

## Behavior

- Pomodoro (25/5 defaults) and custom durations. Each phase is manually started. One shared focus session; device-specific focus blocklists.
- Foreground app tracking all day, independently of whether the UI is open. Windows active-tab tracking; Android browser totals only. Do not count background processes as foreground usage.
- Windows sign-in startup and tray operation. Android uses permitted native background mechanisms. Permission revocation, force-stop, uninstalling, shutdown, and OS restrictions can interrupt operation; disclose failures rather than claiming uninterrupted enforcement.
- Device lock stops counting. Idle handling must not mistake foreground video playback for absence.
- Session blocks, shared daily activity budgets, and recurring scheduled blocks. Any active restriction wins; a break disables only the session restriction.
- Named activities link source identifiers such as a Windows domain and Android package. Shared budgets measure the UNION of that activity's intervals across devices, not their sum. Keep per-device reports separate. Count a shared focus session once.
- An explicit override grants five minutes to the selected app/site on the current device, without stopping tracking or lifting other restrictions. This device scope is the proposed implementation default.
- Work offline with local history/rules and other devices' last confirmed activity. Mark stale devices and pending uploads. Never extrapolate an offline device's open interval beyond its last confirmed observation. Reconcile on reconnection; a global budget can overshoot while disconnected.
- One account timezone determines schedule/day boundaries; timestamps are UTC. Start from the first device's timezone and allow changing it.
- Sync activity identifiers and timestamped intervals. Do not collect page titles, full URLs, screenshots, or keystrokes. Windows executable paths remain local.
- Per-user database isolation from day one. No service-role/admin secrets in clients. No billing or public release in this milestone. Android store acceptance requires separate policy review.

## Interface direction

- Approved direction: **D, Minimal** in the [isolated design comparison](https://github.com/danarrigo/lockin/tree/design/apple-focus-prototype/lib/ui/focus_prototype). Use licensed Inter and Flutter Cupertino Icons, not proprietary Apple fonts.
- Focus shows only the time, one **Lock in** / end control and a small menu, plus quiet build status and genuine error/completion feedback. No dashboard metrics, presets, cards, sidebar, tab bar or prototype controls on this screen.
- Start immediately with the selected duration and current focus rules; do not show a setup form on every start. Duration and focus/break selection belong in the menu and cannot alter a running session. Save duration choices immediately and remember focus/break durations independently, including without starting a session or when a session ends early. Each phase still starts manually; ending early still requires confirmation.
- Use the same composition on phone and desktop. Focus stays dark regardless of system appearance, like the approved Clock-style utility. Windows opens as a compact real window, not a drawn window inside a dashboard. Secondary screens retain system light/dark appearance.
- Keep Activity, Rules, Devices and Settings reachable through the Focus menu. Focused time today belongs in Activity; individual activity budgets belong in Rules. Do not invent a global remaining allowance by summing unrelated limits.
- Show the selected duration while idle, the deadline-based countdown while running, and zero with a completion message when finished. Never display zero before the deadline. No slogans, decorative progress rings or fake live status.
- Keep tracking failures and unfinished enforcement explicit. Use a concise timer-only status and accessible build details, not a misleading live badge.
- Maintain readable contrast, adequate mobile tap targets, and usable forms with the keyboard open.

## Verification

Exercise user-visible timer and rule flows, interval-union budget accounting, timezone/day boundaries, persistence/restart behavior, and native permission/tracking/blocking interfaces. Native background behavior must be verified on Windows and a physical Android device, not inferred from unit tests or a dashboard demo.

## Delivery

Implement and verify vertical slices. Keep unavailable integrations visibly unavailable. Never seed fabricated activity, pretend disconnected devices are live, or advertise background enforcement before it is wired and device-tested.
