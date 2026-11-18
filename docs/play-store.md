# Google Play edition

The `play` flavor is published on Google Play as `app.grindset`. It is the website APK plus optional instant blocking (an Accessibility service). The website APK (`sideload`, `app.lockin.lockin`) stays separate: Play re-signs its builds, so neither can update the other.

CI builds the upload file on every signed run: artifact `grindset-android-play-bundle`, file `app-play-release.aab`, signed with the release key. Under Play App Signing, that key is the upload key and Google holds the app signing key.

## Before the first upload

- Privacy policy: https://danarrigo.github.io/grindset-releases/privacy/
- Account deletion (web): https://danarrigo.github.io/grindset-releases/delete-account/
- The `delete_account` migration (`supabase/migrations/202611180001_delete_account.sql`) must be applied to the hosted project first, or both deletion paths fail with nothing deleted.

## Store listing

- **App name:** Grindset - Focus & App Blocker
- **Short description (80):** Focus timer, screen-time limits and app blocking. No ads, no tracking.
- **Full description:**

  Grindset helps you stay on what matters. Start a focus session, and the apps and websites you chose are blocked until it ends. Take a break with one tap when it does.

  - Focus timer with breaks, and lengths you choose
  - Block apps and websites during focus, on a schedule, or once you hit a daily limit
  - Pick what to block by name: search "Google" or "TikTok", or pick from the apps on your phone
  - See where your time actually goes, per app and per day
  - Optional instant blocking covers a blocked app the moment it opens
  - Optional account to sync rules, focus and usage with Grindset on Windows

  Private by design: works without an account, no ads, no analytics. Grindset records which app was in use and for how long, never what is on your screen or what you type.

  Instant blocking uses Android's Accessibility service, only if you turn it on. It reads only the name of the app that opened, to block it straight away. It does not read screen content or act on your behalf.

- **Category:** Productivity. **Contact email:** your developer email.

## App content answers

**Accessibility (Sensitive permissions > Accessibility API):**

- Core functionality: blocking distracting apps chosen by the user during focus sessions, schedules and limits.
- Not an accessibility tool (`isAccessibilityTool=false`).
- Data accessed: only the package name of the app in front, from window-state-changed events. `canRetrieveWindowContent=false`, so no screen content is read. No actions are performed.
- Prominent disclosure: the "Turn on instant blocking?" dialog, shown before Android's Accessibility settings open, with "Agree and continue".
- Video (Google may ask for one): Settings > Instant blocking > Turn on > the disclosure > Agree > enabling it in Android settings > starting focus > opening a blocked app and seeing the block screen.

**Foreground service (special use):** keeps focus sessions, limits and blocking running while other apps are open; the user can see and stop it from the notification.

**Exact alarms:** the focus and break completion alert must fire on time.

**Data safety:**

| Data type | Collected | Shared | Why | Optional |
| --- | --- | --- | --- | --- |
| Email address | Yes (account only) | No | Account management | Yes |
| App interactions (app/site in use and times) | Yes (sync only) | No | App functionality | Yes |
| Other user-generated content (rules, focus history) | Yes (sync only) | No | App functionality | Yes |

Encrypted in transit: yes. Users can request deletion: yes, in the app and at the web link above. No ads, no analytics. Data that stays on the device is not "collected" in Play's terms.

**Other forms:** Ads: none. Target audience: 13 and over. Content rating questionnaire: a utility with no user-to-user content. Government, financial and health features: none.

## Releasing

A new personal developer account must run a closed test before production: at least 12 testers opted in for 14 days in a row. Upload the `.aab` to a closed testing track, add the testers' Google accounts as an email list, share the opt-in link, and keep at least 12 opted in for the whole 14 days. Then apply for production access in the Console.

Each upload needs a higher `versionCode` than the last; a normal release bump does this.
