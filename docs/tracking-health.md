# Tracking health

**Settings > Tracking health** shows observable prerequisites and recent checks, not a blanket claim that blocking works for every app.

- **Collector:** off/unsupported, permission/service error, or a successful collector-loop check within 15 seconds. Old or future-dated checks are not fresh. Android status comes from the native runtime; Windows foreground-event registration is reported separately.
- **Windows app blocking:** whether foreground monitoring was enabled, plus the most recent app/window presentation verified by the native restriction callback in this launch. Merely invoking a show/focus callback does not count as verification. A successful interruption does not certify other clients, elevated windows, multiple monitors or virtual-desktop boundaries.
- **Android app blocking:** actual Accessibility connection state, separately from Usage Access/background tracking. Connection does not prove every overlay was delivered or that OEM background behavior is reliable.
- **Browser extension:** bridge availability and the most recent authenticated successful policy request. Contact within 75 seconds is recent, allowing for the extension's background alarm. No contact since launch is unknown, not proof of unpairing. Closed/sleeping browsers may show no recent contact. A policy request proves connection, not browser-side rule application. No pairing tokens or browsing content are shown.
- **Restrictions:** current definitions with matching platform sources, not a claim that they are currently active. Tracking-off means enforcement-off. Historical tracking-gap notices remain visible for review.

**Check now** refreshes native collector status without enabling tracking or granting permissions. Setup actions reuse the existing tracking disclosure, Android Accessibility flow and browser pairing UI. Browser contact evidence is reset on disconnect/restart; it is not fabricated from saved configuration. Notification scheduling remains separate from visible-delivery verification.
