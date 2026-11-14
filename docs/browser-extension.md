# Windows browser integration

The unpacked Manifest V3 extension in `extension/` supports Chrome and Edge on Windows. It needs the running Windows app and explicit tracking consent. It is not published or store-reviewed.

## Pairing

1. Open `chrome://extensions` or `edge://extensions`, enable Developer Mode and load the repo's `extension/` directory.
2. In Lockin Settings, select **Pair browser extension**.
3. Open the extension's options and enter the six-digit code. It expires after five minutes and permits five failed attempts. Pair Chrome and Edge separately if using both.
4. Enable tracking in Lockin. Add website sources such as `web:youtube.com` in Rules. A host rule includes its subdomains; do not enter a complete URL, path or wildcard.

The app binds IPv4 loopback port 47831. Pairing issues a random 256-bit bearer token stored in the local journal and trusted extension storage, not cloud usage records. Subsequent requests require the token. Pairing and mutating requests also require a Chrome/Edge extension origin; web-page origins are always rejected. Chrome can omit `Origin` on privileged extension GETs, so only the authenticated, read-only `/v1/rules` route permits that omission. **Disconnect browsers** rotates the token and invalidates all paired clients. Loopback authentication is not protection against malware running as the same Windows user.

If connection requests time out while Lockin is running, check whether the browser's proxy routes loopback traffic through a proxy. The bridge needs a direct connection to `127.0.0.1:47831`. Do not disable general browser security or remove your normal proxy configuration.

## Collection and restrictions

The extension derives a canonical host from Chrome's active-tab API. Only that host, browser identifier, focus and playback booleans cross the bridge. Complete URLs, titles, text and media metadata are neither transmitted nor persisted. The content script checks audio/video playback state without collecting text or media content.

A heartbeat is useful only when the native foreground process is the matching browser. Website intervals end at the last confirmed heartbeat, expire after 12 seconds without an update, and are not extrapolated through disconnection or tracking-off gaps. Browser-app and website intervals overlap, so device totals union them rather than adding both. The native idle probe and foreground-page playback state preserve foreground video counting.

Policy refresh uses the real Dart focus/budget/schedule evaluator. Declarative navigation rules and active-tab checks interrupt restricted domains, including pages already loaded when a rule activates. A five-minute override is source-specific and local to this device. The interruption page reopens only the site's root, never stores/restores the original path or query.

If the native app disconnects, the extension clears its last policy when the next request fails. Foreground-page polling is five seconds; the service-worker fallback alarm is 30 seconds. Do not promise instantaneous fail-open, tamper resistance or enforcement after browser/extension termination. Disabling the extension is a bypass. Incognito access is off unless the user enables it. Multiple profiles of the same browser are not independently identified by this protocol.

## Verification

`node --test extension/*.test.js` verifies host-only parsing, domain matching, declarative policy compilation and override priority. `flutter test test/browser_bridge_test.dart` exercises the real loopback HTTP server, pairing, metadata rejection, the actual controller/SQLite journal, stale observations, native-foreground checks and stop/resume accounting. Windows activity tests mock the OS channel, not the policy or journal.

### Native evidence (Windows build `bc929b5`)

The actual Chrome 157 browser loaded the unpacked extension in a separate profile against the compiled Windows app and an isolated journal. A pre-paired token fixture was used; this does **not** establish the complete user-facing pairing flow.

Verified through the real extension and native HTTP server:

- Authenticated policy reads returned 200; Chrome installed two native domain restrictions.
- An already-open restricted tab was interrupted without navigating it again.
- The real override button reopened only the domain root. Its persisted override covered `web:example.com`, and `example.net` remained restricted.
- A heartbeat containing a full URL and page metadata was rejected with 400. The rejected fixture marker was absent from the SQLite journal and WAL, and no URL-shaped interval sources were stored.
- After quitting the native test process, the extension removed its dynamic restrictions. Following an eight-second settling check, the previously restricted site loaded normally. An immediate navigation can race policy removal; this is not instantaneous fail-open.

The real-browser run found a missing-`Origin` bug that the original HTTP fixtures did not exercise. Chrome omits `Origin` for privileged GETs. The native app now permits that omission only for authenticated `/v1/rules` reads, with regression coverage retaining origin checks for pairing, mutations and web-page requests. The complete 69-test Flutter suite, four extension policy tests, SQL suite and both native CI builds pass on this fix.

The test profile required a direct loopback connection rather than its default proxy route. No normal browser proxy or security settings were changed.

Native Chrome foreground could be acquired briefly but could not be held through the sampling check; no confirmed website intervals were recorded, so this is not evidence of successful end-to-end website accounting. Sustained foreground/media/idle and screen-lock checks, Edge-native checks and physical-device validation remain outstanding. These checks do not establish store acceptance.

### Pairing acceptance (2026-11-13, Windows build `4791d85`)

The unsigned Windows artifact from successful CI run `43363379837` ran with a fresh, isolated `--data-dir`. Selecting **Pair browser extension** in the actual Settings UI displayed a new code. Chrome `157.0.8103.52` loaded the unmodified extension in a separate headless profile through its extension-debugging API. Submitting that code through the real `setup.html` form returned **Paired. Tracking and rules follow the Windows app.** No pre-paired token fixture or direct pairing HTTP request was used.

This verifies the native code-display UI and extension form/worker/bridge pairing path, but not manually loading the extension in a visible browser, Edge, sustained native foreground website accounting or enforcement. The normal Chrome profile/proxy configuration was not changed.

### Headful Chrome accounting, idle and video (2026-11-13, `14b597f`)

The real Windows artifact from CI run `43403540374` paired through its displayed code and the real extension setup form in headful Chrome `157.0.8103.52`. A controlled `example.org` page was fulfilled locally through CDP; it displayed a genuine paused/playing muted canvas video. CDP loaded the extension and controlled only this test profile. No token fixture, fabricated journal interval, normal-profile change or security exclusion was used.

Native foreground PID checks and SQLite snapshots verified a fresh, sustained `web:example.org` interval. An initial idle attempt was explicitly blocked after Windows input reset the idle clock; it was not counted as passing. The bounded retry observed Chrome still foreground with native idle at `207906 ms`. Website counting had stopped at the last confirmed heartbeat, `10:52:56.447 UTC`.

Starting the actual foreground muted video without Windows input resumed website accounting from `10:53:31.931` through `10:53:51.442 UTC`, despite native idle exceeding three minutes. Pausing the video left that interval unchanged after another 15 seconds. This verifies the Windows idle plus foreground-page playback path, not desktop-player GSMTC/audio behavior or screen-lock boundaries.

Headful Edge `157.0.4341.46` also paired through the real setup form. Its accounting attempt did not pass: an OS-account automatic-sign-in/sync popup took foreground instead of the controlled page. No sync consent was accepted and no personal browsing data was inspected. The attempt was stopped and only its isolated profile/cache was removed; normal browser profiles and Windows account settings were not changed. That run did not establish account-free Edge acceptance; manually loading the extension through browser UI, desktop-player media and screen-lock checks remain separate.

### Essential blocking/override follow-up (2026-11-13)

Headful Chrome `157.0.8103.52` and Edge `157.0.4341.46` both passed the actual restriction-page and five-minute override flow against the native Windows app. The existing controlled activity already had six minutes of genuinely observed website usage; its budget was temporarily changed from 30 to one minute through Rules, not by inventing intervals or injecting browser policy.

Each browser loaded the unmodified extension and paired through the app's displayed code and the real setup form. Chrome interrupted `example.org` with **Daily budget reached**. Its real override button reopened exactly `https://example.org/`, dropping the controlled path/query, while `example.net` remained blocked. Edge then independently interrupted `example.net` and its override reopened exactly `https://example.net/`. Browser debug loading did not persist across the earlier restart, so a navigation attempt without an extension worker was discarded rather than counted as an enforcement failure.

For Edge, the automatically linked identity was signed out through only the isolated test profile's own Settings/confirmation UI. The profile then offered **Sign in**, not **Sign out**; normal profiles and Windows account policies were untouched. The earlier cached-account count was not used as proof of active sign-in. Both test browsers were closed and the Edge test profile removed afterward. The temporary activity budget was restored to 30 through an owner-authenticated, revision-checked RPC during cleanup. This verifies functional blocking/override in both browsers, not full native Edge accounting or every onboarding path.
