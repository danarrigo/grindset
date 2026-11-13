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
