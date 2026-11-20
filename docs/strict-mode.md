# Strict mode

A switch in Settings, shared by all of an account's devices (shared setting `strict_mode` = `{"enabled": bool}`).

It is **locked** while any of these holds (`AppController.strictLock`):

- a focus session is running,
- Focus hours are on,
- a rule's daily limit is reached, or a rule's set times are on.

While locked, `AppController` refuses with `StrictModeLocked`:

- ending a focus session early,
- deleting a rule or saving it less strict (`isStricter`: no app removed, no higher or removed limit, "While I'm focusing" and every set time kept),
- shortening or turning off Focus hours, switching focus profiles, changing the timezone,
- stopping tracking, resetting the device, turning strict mode off.

Making things stricter always works.

## Keeping Grindset running

- **Android**: the notification's Stop button is ignored, and Android's uninstall screen (`com.android.packageinstaller`, `com.google.android.packageinstaller`) is blocked like a restricted app (`setStrictLock`). Removing permissions in Settings is not prevented.
- **Windows**: Quit is disabled in the tray, and a per-user scheduled task `Grindset strict mode` starts `lockin.exe --background` every minute; a single-instance mutex in `windows/runner/main.cpp` makes extra starts exit. The task is removed when the lock ends and on uninstall.
- **Browsers**: while websites are blocked, a browser in front whose extension has not reported for 10 seconds is blocked as a whole app. Browsers the extension cannot report from (Brave, Opera) are always blocked while locked.

Uninstalling Grindset on Windows is not prevented.
