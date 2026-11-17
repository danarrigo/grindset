# Setup checklist

**Settings > Setup** lists what must be done before rules can work on this device. Each step shows a done tick, a single action button, or a red mark when something broke. Only the next unfinished step gets the prominent button. Until every step is done, the Focus screen shows **Finish setup · N of M done**, and the header shows **Finish setup** (or **Needs attention** for a broken step, **Tracking on** when complete).

- **Activity tracking:** on, off, or stopped (an error, a missing permission, or on Android a stopped background service). **Turn on** / **Fix** opens the tracking disclosure, then Android's Usage access and notification prompts.
- **App blocking (Android):** whether Display over other apps is allowed. **Set up** explains the permission and opens Android's list, where the person taps Grindset.
- **App blocking (Windows):** whether foreground monitoring is running while tracking is on.
- **Browser extension (Windows):** connected when an authenticated policy request arrived within the last 75 seconds. Closed or sleeping browsers may show not connected. **Pair** opens browser pairing.
- **Rules:** rules with matching sources for this platform and a focus block, daily limit or schedule. **Add rule** opens Rules.

The refresh button re-reads native collector status without enabling anything. A done step means its prerequisite is met, not that every app or window will be blocked; operating systems can still stop Grindset in the background.
