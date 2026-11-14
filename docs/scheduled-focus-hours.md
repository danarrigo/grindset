# Scheduled focus hours

In **Rules > Schedule focus hours**, choose the apps/websites to restrict, select weekdays and times, then save. This creates a normal editable activity named Focus hours. It starts with weekday 09:00-17:00, no daily budget and no timer-only focus blocking; nothing is saved or enabled automatically.

Schedules restrict the selected sources even when no timer is running. Use **Add time window** for split work periods, evenings or separate weekend hours. Editing preserves every existing window, budget and activity identity. At least one weekday and different start/end times are required for each window. Up to 64 windows are supported.

The editor and rule summary show the account timezone. An overnight window belongs to its starting weekday: Monday 22:00-02:00 includes early Tuesday. Boundaries are start-inclusive and end-exclusive; daylight-saving behavior follows the account's named timezone. Multiple windows combine as restrictions, not as additional timers. Overlapping rules still apply independently.

Tracking and the relevant blocking integration must be enabled. Windows needs Grindset running; website restrictions additionally need the paired browser extension. Android needs background tracking and the optional Accessibility service for app blocking. Quitting/turning tracking off stops enforcement; schedules do not create a service or bypass OS permissions. Physical Android background reliability remains a separate acceptance boundary.

A five-minute source override temporarily allows that source during its schedule. Canceling the editor does not change rules. Turning off Scheduled focus hours and saving explicitly removes that activity's windows. Other activities remain unchanged.
