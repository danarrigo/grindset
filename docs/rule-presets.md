# Starter activities and desktop coverage

Rules offers **All social media** plus 17 individual activities: Instagram, YouTube, TikTok, Reddit, X, Facebook, Snapchat, Twitch, Discord, WhatsApp, Telegram, Signal, Messenger, LinkedIn, Pinterest, Threads and Bluesky. The combined rule covers this supported catalog, not literally every social service or unofficial client.

Select a starter, review its sources, suggested **30 minutes per day** and **Block during focus**, then save. Nothing is automatically persisted or enforced. Tracking and OS permissions remain opt-in. Individual activities have separate budgets; All social media has one combined budget, unioning overlapping usage across all selected sources/devices. Existing individual restrictions still apply alongside it. There is no default recurring schedule. Focus-block flags remain device-local; daily budgets and schedules synchronize.

## Windows apps

The Discord starter includes `windows:discord.exe`, `windows:discordptb.exe` and `windows:discordcanary.exe`. Telegram includes `windows:telegram.exe`; Signal includes `windows:signal.exe`; WhatsApp includes the distinct `windows:whatsapp.exe` and `windows:whatsapp.root.exe` process names. These are app-specific executable identifiers, never generic browser/WebView hosts. Windows executable matching is case-insensitive; Android package matching remains case-sensitive.

Windows tracking must be enabled and a focus, budget or schedule restriction active. The existing foreground restriction mechanism brings Grindset's interruption window forward; it is voluntary enforcement, not process termination or tamper/uninstall protection. Returning to a restricted app after an observed foreground transition reopens the interruption. A source-specific five-minute override still leaves other restrictions active.

Older saved rules are not silently broadened. **Add desktop coverage** on a recognized activity opens its normal editor with missing Windows identifiers preselected. Saving preserves its ID, name, budget, schedules and local focus flag. Cancelling leaves it unchanged. The editor has readable labels, search and selected sources first.

Known Windows names were checked against [Discord testing clients](https://support.discord.com/hc/en-us/articles/360035675191-Discord-Testing-Clients), [Telegram's installer source](https://github.com/telegramdesktop/tdesktop/blob/dev/Telegram/build/setup.iss) and [Signal Desktop](https://github.com/signalapp/Signal-Desktop). Alternative/repackaged clients may use other identifiers; use an observed app source when necessary. Store/PWA apps using shared browser hosts are not indiscriminately blocked by executable name.

## Websites and Android

Website rules include subdomains and need the paired Windows browser extension. Android requires tracking and the optional Accessibility blocking service. A starter does not claim an app is installed, fabricate usage, grant permissions or inspect page/screen contents. The catalog is bundled and makes no network requests while choosing suggestions.

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
