# Websites on Windows without the extension

When the Grindset extension is not reporting from the browser in front, Windows reads the site from the browser's address bar through UI Automation (`activityState` with `browser: true` in `windows/runner/activity_probe.cpp`):

- Chromium browsers (Chrome, Edge, Brave, Opera): the element whose class is `OmniboxViewViews`.
- Firefox-based browsers (Firefox, Zen and others): the element with id `urlbar-input`.

Only the host is returned; paths and queries are dropped in native code. While the bar has keyboard focus (someone typing), the last site is kept.

The site counts as web usage, like the extension's reports. When it is blocked, Grindset closes that tab (Ctrl+W, sent only while the browser is still in front) and shows a notification. In strict mode, a browser whose site can be read is no longer blocked as a whole.

Limits: a browser update that renames these elements stops this until the names are updated; the extension remains the preferred way, since it shows a block page in the tab and knows when media plays.
