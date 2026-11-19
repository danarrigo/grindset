# Starter rules, search and desktop coverage

Rules offers **All social media** plus 17 individual starters: Instagram, YouTube, TikTok, Reddit, X, Facebook, Snapchat, Twitch, Discord, WhatsApp, Telegram, Signal, Messenger, LinkedIn, Pinterest, Threads and Bluesky. The combined rule covers this supported catalog, not literally every social service or unofficial client.

Select a starter, review its sources, suggested **30 minutes per day** and **Block during focus**, then save. Nothing is automatically persisted or enforced. Tracking and OS permissions remain opt-in. Individual rules have separate budgets; All social media has one combined budget, unioning overlapping usage across all selected sources/devices. Existing individual restrictions still apply alongside it. There is no default recurring schedule. Focus-block flags remain device-local; daily budgets and schedules synchronize.

## Choosing apps and websites

Search by the name people know: **Google**, **ig**, **twitter**, **netflix**. Results come from:

- **The built-in service list** ([`lib/core/service_catalog.dart`](../lib/core/service_catalog.dart)): about 150 popular services, each with its websites, Android app and Windows app, plus nicknames. It is bundled and searched offline.
- **Whole companies**: **All of Google**, **Microsoft**, **Meta** and **Amazon** add every listed service in one tap. Expand one to untick parts, for example Gmail. Unticking a part removes only what that part covers. Because website rules include subdomains, keeping `google.com` still covers Gmail on `mail.google.com`. Whole browsers are never part of a company.
- **Apps on this device**: apps this device has used, and on Windows the apps found with **Show apps on this PC** or **Browse**. Picking a known service here adds all of it.
- **Exactly what was typed**: a website (`example.com`) or an app ID (`android:com.example`, `windows:app.exe`). Enter adds the top result.

Apps show their installed icon when they are installed on this device: Android reads it from the package manager, and Windows reads it from the running process or its App Paths registration (never a disk search). Everything else shows a letter tile. No icons are fetched from the internet.

**Schedule focus hours** opens a schedule-only editor. See [scheduled focus hours](scheduled-focus-hours.md).

On Windows, **Show apps on this PC** reads visible running applications and App Paths registrations on demand, off the UI thread. Labels come from executable version metadata, never window titles. **Browse** selects an executable without launching it; only its executable name is saved, not its path. This is not a complete installed-package inventory: elevated apps can be inaccessible, launchers can use a different foreground executable, and Store/PWA apps may share hosts. Windows recovery/system hosts and Grindset itself are excluded. Choosing an app does not grant tracking consent or save a rule.

## Windows apps

The Discord starter includes `windows:discord.exe`, `windows:discordptb.exe` and `windows:discordcanary.exe`. Telegram includes `windows:telegram.exe`; Signal includes `windows:signal.exe`; WhatsApp includes the distinct `windows:whatsapp.exe` and `windows:whatsapp.root.exe` process names. These are app-specific executable identifiers, never generic browser/WebView hosts. Windows executable matching is case-insensitive; Android package matching remains case-sensitive.

Windows tracking must be enabled and a focus, budget or schedule restriction active. Restricted native apps are minimized when they enter foreground. Grindset presents a borderless restriction screen covering that app's monitor, with no desktop navigation or movable title bar. Closing/minimizing the restriction frame does not dismiss it. Foreground events trigger immediate checks, with polling as a fallback; Alt-Tab back to a restricted app reapplies enforcement. **Use other apps** dismisses the explanation, not the rule. There is no temporary override: a blocked app stays blocked until its focus session, schedule or day ends. Allowed apps restore the normal Grindset window and remove its topmost presentation. This remains voluntary enforcement, not process termination or tamper/uninstall protection; Windows recovery controls and deliberate quitting remain available. Apps that refuse minimization are reported as unblocked rather than falsely claimed locked.

Older saved rules are not silently broadened. **Add desktop coverage** on a recognized rule opens its normal editor with missing Windows identifiers preselected. Saving preserves its ID, name, budget, schedules and local focus flag. Cancelling leaves it unchanged. The editor has readable labels, search and selected sources first.

Known Windows names were checked against [Discord testing clients](https://support.discord.com/hc/en-us/articles/360035675191-Discord-Testing-Clients), [Telegram's installer source](https://github.com/telegramdesktop/tdesktop/blob/dev/Telegram/build/setup.iss) and [Signal Desktop](https://github.com/signalapp/Signal-Desktop). Alternative/repackaged clients may use other identifiers; use an observed app source when necessary. Store/PWA apps using shared browser hosts are not indiscriminately blocked by executable name.

## Websites and Android

Website rules include subdomains and need the paired Windows browser extension. Android requires tracking and the optional Display over other apps permission for blocking. A starter does not claim an app is installed, fabricate usage, grant permissions or inspect page/screen contents. The catalog is bundled and makes no network requests while choosing suggestions.

The authoritative identifiers are in [`lib/core/rule_presets.dart`](../lib/core/rule_presets.dart). Main Android packages were checked against publisher Google Play listings:

| Activity | Android package |
| --- | --- |
| Instagram | [com.instagram.android](https://play.google.com/store/apps/details?id=com.instagram.android) |
| YouTube | [com.google.android.youtube](https://play.google.com/store/apps/details?id=com.google.android.youtube) |
| TikTok | [com.zhiliaoapp.musically](https://play.google.com/store/apps/details?id=com.zhiliaoapp.musically), [com.ss.android.ugc.trill](https://play.google.com/store/apps/details?id=com.ss.android.ugc.trill) |
| Reddit | [com.reddit.frontpage](https://play.google.com/store/apps/details?id=com.reddit.frontpage) |
| X | [com.twitter.android](https://play.google.com/store/apps/details?id=com.twitter.android) |
| Facebook | [com.facebook.katana](https://play.google.com/store/apps/details?id=com.facebook.katana) |
| Snapchat | [com.snapchat.android](https://play.google.com/store/apps/details?id=com.snapchat.android) |
| Twitch | [tv.twitch.android.app](https://play.google.com/store/apps/details?id=tv.twitch.android.app) |
| Discord | [com.discord](https://play.google.com/store/apps/details?id=com.discord) |
| WhatsApp | [com.whatsapp](https://play.google.com/store/apps/details?id=com.whatsapp) |
| Telegram | [org.telegram.messenger](https://play.google.com/store/apps/details?id=org.telegram.messenger) |
| Signal | [org.thoughtcrime.securesms](https://play.google.com/store/apps/details?id=org.thoughtcrime.securesms) |
| Messenger | [com.facebook.orca](https://play.google.com/store/apps/details?id=com.facebook.orca) |
| LinkedIn | [com.linkedin.android](https://play.google.com/store/apps/details?id=com.linkedin.android) |
| Pinterest | [com.pinterest](https://play.google.com/store/apps/details?id=com.pinterest) |
| Threads | [com.instagram.barcelona](https://play.google.com/store/apps/details?id=com.instagram.barcelona) |
| Bluesky | [xyz.blueskyweb.app](https://play.google.com/store/apps/details?id=xyz.blueskyweb.app) |

Catalog and widget/controller/SQLite tests cover combined accounting, native-source selection, explicit legacy coverage upgrades, preservation of custom rules, cancellation and desktop/mobile layouts. Native and physical-device reliability are separate from these tests.
