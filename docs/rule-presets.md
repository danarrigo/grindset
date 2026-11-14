# Starter activities

Rules offers Instagram, YouTube, TikTok, Reddit, X, Facebook, Snapchat, Twitch and Discord without requiring anyone to look up package identifiers. These are bundled suggestions, not claims that those apps are installed or have recorded usage.

Selecting a starter opens the normal activity editor with its website hosts and Android packages selected, **30 minutes per day** and **Block during focus** enabled. Review or change these choices, then choose **Save activity**. Cancelling saves nothing. No rule, tracking opt-in, OS permission or cloud policy changes merely by opening Rules.

Saved starters are ordinary editable/deletable activities with the existing shared-budget, persistence, conflict and sync behavior. The limit applies separately to each activity and unions overlapping usage across its linked sources. There is no blanket combined social-media allowance and no default recurring schedule. Existing activities are never replaced; suggestions whose sources overlap an existing activity are hidden, including matching website subdomains. Deleted activities are not automatically recreated.

The editor also lists the known starter identifiers alongside observed/custom sources, with readable app names. Manual identifiers remain available for other apps, work-profile clones and variants. Nothing is fetched or installed while browsing suggestions.

## Coverage

Website rules include subdomains and need the paired Windows extension. Android rules match exact package IDs and require the existing tracking/Accessibility opt-ins. These starters do not identify Windows desktop executables, distinguish YouTube Shorts from other YouTube use, or grant any extra enforcement capability.

The catalog is maintained in [`lib/core/rule_presets.dart`](../lib/core/rule_presets.dart). Main Android package IDs were checked against the publishers' Google Play listings on 2026-11-14:

| Activity | Website hosts | Official Android listing |
| --- | --- | --- |
| Instagram | `instagram.com` | [com.instagram.android](https://play.google.com/store/apps/details?id=com.instagram.android) |
| YouTube | `youtube.com`, `youtu.be` | [com.google.android.youtube](https://play.google.com/store/apps/details?id=com.google.android.youtube) |
| TikTok | `tiktok.com` | [com.zhiliaoapp.musically](https://play.google.com/store/apps/details?id=com.zhiliaoapp.musically), [com.ss.android.ugc.trill](https://play.google.com/store/apps/details?id=com.ss.android.ugc.trill) |
| Reddit | `reddit.com`, `redd.it` | [com.reddit.frontpage](https://play.google.com/store/apps/details?id=com.reddit.frontpage) |
| X | `x.com`, `twitter.com` | [com.twitter.android](https://play.google.com/store/apps/details?id=com.twitter.android) |
| Facebook | `facebook.com` | [com.facebook.katana](https://play.google.com/store/apps/details?id=com.facebook.katana) |
| Snapchat | `snapchat.com` | [com.snapchat.android](https://play.google.com/store/apps/details?id=com.snapchat.android) |
| Twitch | `twitch.tv` | [tv.twitch.android.app](https://play.google.com/store/apps/details?id=tv.twitch.android.app) |
| Discord | `discord.com` | [com.discord](https://play.google.com/store/apps/details?id=com.discord) |

Tests exercise the real Rules/editor/controller/SQLite flow: review/cancel, editable defaults, persistence, existing-rule preservation, overlap filtering and a short phone at double text size. A widget-rendered [Rules preview](../test/goldens/mobile-rule-starters.png) captures the initial state. Identifier catalog checks do not establish physical-device enforcement reliability.
