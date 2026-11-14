# Windows app restriction acceptance

## v1.3.0 desktop/preset checks

Widget/controller/SQLite tests exercise persistent desktop navigation, keyboard shortcuts without stopping the timer, multi-column Rules/Settings, the All social media rule, explicit desktop-source upgrades without changing existing budgets/focus flags, Windows case-insensitive identifiers and repeated foreground-entry callbacks. Goldens cover the desktop workspaces and unchanged compact/mobile timer composition.

## Native Discord check (2026-11-14)

The first compiled candidate (`bcec3be`) used an isolated journal with `--local-only --no-alerts`, with tracking enabled through the real disclosure and the Discord starter reviewed/saved through the real editor. An independent Windows SQLite read verified the five Discord sources, focus blocking enabled and the 30-minute limit. No cloud account was linked. The normal browser bridge was already occupied by the owner's existing installation; it was left alone because this check concerned native apps, not websites.

The actual Discord process entered the foreground during a real focus session. Grindset rendered **Discord is restricted / Focus session in progress**, but the OS foreground remained Discord. Scheduling a focus call was therefore not a successful interruption. The generic window-manager focus API silently discarded Windows activation refusal.

Candidate `977016c`, from successful CI run `43586566264`, adds an own-window native activation operation on the Windows UI thread. It temporarily attaches the foreground input queue, restores/raises Grindset, detaches the queue and checks that the owned window actually became foreground. No global foreground-lock settings, synthetic keyboard input, process suspension, other-app titles or message contents are used. Failure is surfaced rather than silently treated as success.

With the same real-editor/preset flow in a fresh isolated journal, an actual foreground transition from Discord PID 25488 to the owned Grindset PID 9844 was observed. This establishes one successful real Discord foreground interruption after the fix. Repeated-entry and override paths pass controller/lifecycle tests; further native repeat/override attempts were inconclusive because the automation could not reliably reactivate the Discord window. They are not recorded as native passes. No Discord chats or private window contents were inspected or captured.

Only the owned previews were closed. Their local tracking/alert opt-ins were disabled, no cloud owner was ever linked, the normal installation/bridge/startup entry were preserved, and notification scheduling was skipped entirely. This is voluntary foreground interruption, not a hard process lock or physical-device/whole-Windows certification. Additional clients, elevated apps, workspace boundaries and native repeated/override acceptance remain separate checks.
