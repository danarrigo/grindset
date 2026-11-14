# Windows app restriction acceptance

## v1.3.1 escape-path regression (2026-11-14)

Candidate `c88d541` replaces the warning-only mechanism with verified foreground-app minimization plus a monitor-sized, borderless/topmost explanation. A Windows foreground-event listener runs only while tracking is enabled; polling remains a fallback. Native methods validate the actual foreground PID, executable and user session before acting. Desktop/security/recovery processes and Grindset itself are excluded. Closing, minimizing or repositioning the active frame cannot silently uncover the same restricted app. The normal window placement/styles are restored without forcing an allowed app out of foreground. Policy expiry is evaluated even while Grindset owns foreground, and enforcement is independent of idle usage accounting.

Acceptance used two empty owned Windows Forms executables, one restricted and one allowed, not Discord chats or normal browser profiles. The rule, tracking disclosure and real 25-minute focus sessions were saved through the installed UI in an isolated `--local-only --no-alerts` journal. The same journal was upgraded from the v1.3.0 portable build to the candidate.

- `check-escape.ps1 -Baseline -StartFixtures` went red (exit 2): the real restricted process entered foreground and Grindset returned foreground, but the target was **not minimized**, and the restriction bounds were `[400,216,1520,936]` inside a `[0,0,1920,1200]` monitor.
- The candidate minimized the same app and used exact `[0,0,1920,1200]` bounds.
- `verify-input.ps1` used guarded real pointer input on owned windows, including **Use other apps** followed by another restricted-app activation. Five consecutive returns passed; a later five-return run measured 47–109 ms. Background programmatic activation attempts were not counted as equivalent to real input when Windows did not grant foreground.
- `check-alt-tab.ps1` sent an actual Alt-Tab from the owned restriction window and observed Explorer, then the restricted PID, then Grindset. The restricted app ended minimized and the frame again covered the full monitor.
- `verify-override.ps1` passed close, system-close, minimize and move/resize attempts; an allowed application regained foreground with no topmost covering frame; returning to the restricted app reapplied the block. Clicking the real five-minute override persisted an actual expiry, restored the target, removed the full-screen presentation and left the target usable across subsequent polling.
- A real session expired during acceptance; blocking stopped without modifying the clock or fabricating usage. The next session was started through the normal UI.

Only owned windows were captured. The preview and both fixtures were closed, its local tracking/alert opt-ins disabled, and absence of a linked cloud owner verified. The normal installation, browser bridge, profiles and startup entry were untouched. Raw journals, screenshots and script output are retained locally under the owned `grindset-v1.3.1-acceptance` temporary directory.

These are real Windows foreground/window-management checks with controlled applications, not certification of every native client, elevated windows, multiple monitors/DPI combinations or physical Android reliability. Windows/user recovery and deliberate quitting remain available; this is not tamper-proof process or OS lockdown.

## v1.3.0 desktop/preset checks

Widget/controller/SQLite tests exercise persistent desktop navigation, keyboard shortcuts without stopping the timer, multi-column Rules/Settings, the All social media rule, explicit desktop-source upgrades without changing existing budgets/focus flags, Windows case-insensitive identifiers and repeated foreground-entry callbacks. Goldens cover the desktop workspaces and unchanged compact/mobile timer composition.

## Native Discord check (2026-11-14)

The first compiled candidate (`bcec3be`) used an isolated journal with `--local-only --no-alerts`, with tracking enabled through the real disclosure and the Discord starter reviewed/saved through the real editor. An independent Windows SQLite read verified the five Discord sources, focus blocking enabled and the 30-minute limit. No cloud account was linked. The normal browser bridge was already occupied by the owner's existing installation; it was left alone because this check concerned native apps, not websites.

The actual Discord process entered the foreground during a real focus session. Grindset rendered **Discord is restricted / Focus session in progress**, but the OS foreground remained Discord. Scheduling a focus call was therefore not a successful interruption. The generic window-manager focus API silently discarded Windows activation refusal.

Candidate `977016c`, from successful CI run `43586566264`, adds an own-window native activation operation on the Windows UI thread. It temporarily attaches the foreground input queue, restores/raises Grindset, detaches the queue and checks that the owned window actually became foreground. No global foreground-lock settings, synthetic keyboard input, process suspension, other-app titles or message contents are used. Failure is surfaced rather than silently treated as success.

With the same real-editor/preset flow in a fresh isolated journal, an actual foreground transition from Discord PID 25488 to the owned Grindset PID 9844 was observed. This establishes one successful real Discord foreground interruption after the fix. Repeated-entry and override paths pass controller/lifecycle tests; further native repeat/override attempts were inconclusive because the automation could not reliably reactivate the Discord window. They are not recorded as native passes. No Discord chats or private window contents were inspected or captured.

Only the owned previews were closed. Their local tracking/alert opt-ins were disabled, no cloud owner was ever linked, the normal installation/bridge/startup entry were preserved, and notification scheduling was skipped entirely. This is voluntary foreground interruption, not a hard process lock or physical-device/whole-Windows certification. Additional clients, elevated apps, workspace boundaries and native repeated/override acceptance remain separate checks.
