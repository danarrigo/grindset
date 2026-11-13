# Completion alerts

Alerts are opt-in in Settings and independent of tracking. One OS schedule (ID 4302) is replaced/cancelled when a timer changes or alerts are disabled. Starting the next phase remains manual. UTC deadlines are rounded up to the next whole second because the notification SDK serializes seconds; an alert must not claim completion before the real deadline.

Android uses the platform notification/alarm APIs. Exact alarms require separate permission. If exact permission is denied, an inexact alarm is scheduled and the UI explicitly warns that delivery can be delayed. Windows uses toast scheduling. Disabling OS notifications, OEM battery management, force-stop and other OS policies can suppress delivery. Unpackaged Windows supports pending-schedule cancellation, but removing already-delivered toasts requires package identity.

## Verified evidence

- Dart/controller/real SDK tests cover opt-in, UTC scheduling, early cancellation, permission denial, inexact fallback, shared-session changes, persisted restoration, retryable initialization, clock skew and in-flight scheduling races. Only the OS method-channel boundary is mocked.
- Both native builds and the complete 68-test Flutter suite pass on the notification implementation. Native build checks are in GitHub Actions.
- On the dedicated API 36.1 emulator, the actual **Lock in** button started a one-minute session at `2026-11-12T01:17:11.415729Z`, ending at `01:18:11.415729Z`. Android AlarmManager recorded an exact RTC wakeup for `01:18:12.000Z`. The UI was closed and the background process was killed before the deadline; `pidof` was empty. NotificationManager subsequently recorded notification 4302, channel `lockin_completion`, title **Focus complete**, posted at `01:18:12.775Z`. A real notification-shade capture confirmed it. Activity tracking was not enabled. Notification/exact-alarm permissions were supplied as controlled emulator fixture state; this does not establish every permission-dialog flow or OEM behavior.
- Windows accepted the real app's alert into its OS toast schedule with tag 4302 and the correct generic title/body. A native regression check on commit `3986b5e` also scheduled a session whose start was two minutes ahead of the receiving clock: start `01:26:31.724934Z`, end `01:27:31.724934Z`, OS schedule `01:27:32Z`. Visual Windows delivery is not yet verified.

## Clock-skew regression

The emulator clock lagged the host during native testing. The initial implementation required the receiving device to consider the session already running, so a slightly future shared start could silently skip its end alert. Scheduling now checks whether the confirmed **end** is still in the future. This fixes the native reproduction and is covered by a regression test. It does not change usage accounting or extrapolate disconnected activity.

## Windows cancellation acceptance (2026-11-13)

The real Windows artifact for `4791d85` from successful CI run `43363379837` ran with a fresh, isolated `--data-dir`, tracking disabled and no signed-in account. Through the actual UI, completion alerts were enabled and the duration changed to one minute:

- **Lock in** created OS toast schedule tag `4302`, title **Focus complete**, deadline `2026-11-13T04:58:13Z`. Confirming **End session** before the deadline removed it from `ToastNotifier.GetScheduledToastNotifications()`.
- A later one-minute session created tag `4302` for `05:10:27Z`. Turning off **Completion notifications** in Settings while the timer was still running removed the pending schedule too.

These are native scheduling/cancellation checks, not mocked method channels. A subsequent schedule expired, but no visible toast was captured, so visual delivery remains unverified. No OS notification settings were weakened to claim delivery.

## Still required

Physical Android delivery, notification and exact-alarm revocation, inexact delivery behavior, OEM battery restrictions and Windows visual delivery. Cloud-driven timer changes need live Supabase validation; HTTP/controller tests are not a substitute. Do not label an alert delivered merely because a scheduling API returned success.
