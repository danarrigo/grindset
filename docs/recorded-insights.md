# Recorded weekly insights

Choose **Activity > Weekly insights**. The view reads this device's confirmed intervals for the last seven local calendar days, including the partial current day, in the current account timezone. It loads when opened, refreshes every minute while visible and has a manual refresh action. Other devices' intervals are excluded. No missing activity is estimated or backfilled.

Overall usage and usage matching current activities union overlapping intervals. App/site breakdowns may overlap and must not be summed to reconstruct the overall total. A day with no observations says **Not recorded**, not zero usage. Coverage counts days with any observations, not complete 24-hour coverage. Nothing infers productivity, attention or good/bad behavior from an executable name or a tracking gap.

Budget comparisons apply **current** daily limits and source selections to this device's historical observations. They show when this device alone reached a limit; other devices may have contributed to the same shared budget sooner. They are explicitly not a historical audit of the limits that were configured at that time. Overnight intervals are clipped at named-timezone calendar-day boundaries, including 23/25-hour daylight-saving days. Future endpoints are clipped at the snapshot time. Editing a budget can therefore change this comparison without changing recorded data.

The view is a read-only projection of the existing journal. It does not manufacture sessions, rewrite intervals or upload aggregate scores.
