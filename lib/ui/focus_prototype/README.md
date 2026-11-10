# Throwaway Focus-screen prototype

Question: which real Apple-app structure should guide Lockin's focus-first screen? These are deliberately different compositions, not three palette swaps.

**Verdict: awaiting user review. Do not merge this prototype into main.** The production Flutter entrypoint, database, tracking and cloud modules are not used or mutated here.

## Run

```sh
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=4173 --target=lib/ui/focus_prototype.dart
```

Open:

- A, Clock: <http://localhost:4173/?variant=A>
- B, Focus settings: <http://localhost:4173/?variant=B>
- C, Control panel: <http://localhost:4173/?variant=C>

The bottom prototype bar cycles with its arrows or the left/right keyboard keys. The info button shows the complete in-memory state. Duration and timer actions are simulated locally; there is no persistence, app blocking, account or fabricated usage history. Clicking a secondary navigation item explains that it is outside this visual prototype.

The prototype and switcher are unavailable in release builds. The default `lib/main.dart` remains the real app. The temporary web platform and icon dependency belong to the design branch only until a direction is accepted.

## Captured previews

| Direction | Desktop | Phone |
| --- | --- | --- |
| A, Clock | [View](previews/a-desktop.png) | [View](previews/a-mobile.png) |
| B, Focus settings | [View](previews/b-desktop.png) | [View](previews/b-mobile.png) |
| C, Control panel | [View](previews/c-desktop.png) | [View](previews/c-mobile.png) |

[Running Focus-settings state](previews/b-running-desktop.png). Captured from the actual browser preview, not a generated illustration.

## Directions and sources

- **A, Clock:** a high-contrast working surface, large timer numerals, circular actions, flat rows and a floating native-style tab bar. Based on [Apple's Clock app](https://apps.apple.com/us/app/clock/id1584215688), using screenshots returned by Apple's public [App Store lookup](https://itunes.apple.com/lookup?id=1584215688). No Apple screenshots or proprietary fonts are bundled.
- **B, Focus settings:** grouped native preferences, a clear focus-mode identity, a system-blue start action and a contextual desktop sidebar. The phone keeps the same content hierarchy.
- **C, Control panel:** a compact focus control with restrained translucent material, plus a separate status list. Material is limited to the functional controls/navigation, following [Apple's materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials), not spread across a glass dashboard.

Typography uses the existing licensed Inter asset. Symbols use the Flutter Cupertino Icons package, not an Apple SF Symbols font.

After choosing a direction, rewrite the winner properly in the actual Flutter screen, validate the real flows, and keep this comparison on its throwaway branch as the primary design source.
