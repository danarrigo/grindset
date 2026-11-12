# Device data and account switching

## Export

Settings > **Export data** creates a private JSON archive. Windows uses a save-file dialog; Android uses the system document picker, without broad storage permissions. Cancelling the picker changes no app data.

The archive is a consistent SQLite snapshot, then streamed off-thread in batches of at most 500 rows. It includes settings from an explicit allowlist, all confirmed/pending intervals, timer history, canonical shared state, pending offline edits and saved conflicts. The live database is not held open while the user chooses a destination. Private temporary snapshot/output directories are removed afterward.

Format `lockin-export`, version `1`, records the UTC export time and SQLite schema version. Table rows retain their stored fields; interval timestamps are UTC epoch milliseconds. JSON-valued table fields/settings remain JSON strings. Auth credentials, browser pairing tokens and unknown future settings are excluded. Device/account identifiers and activity timestamps are personal data: the archive is not anonymous and should be stored securely. There is no automatic archive-import feature.

## Sign-out and another account

Sign-out keeps history and its original account binding. Another account cannot upload or adopt that journal. The login UI signs the mismatched account back out and directs the user to export/reset first; the sync protocol independently refuses mismatched owners before uploads.

To change accounts: export anything worth retaining, choose **Reset this device**, confirm **Reset and close**, reopen Lockin, and sign in to the other account. This is deliberately a restart, not a hot swap of SQLite/auth ownership.

## Reset

Reset affects this device only:

1. Stop polling and tracking, wait for the current observation, cancel scheduled completion alerts, rotate browser credentials and drain/close browser requests.
2. Stop automatic sync and await outstanding requests. An already-sent upload may have reached the account; reset is not a cloud deletion operation.
3. Sign out locally. Remote logout is best-effort when offline; other devices are not signed out. Auth persistence is serialized and sealed so a delayed refresh cannot restore the session after reset.
4. Delete local settings, history, account binding, revisions, pending edits and conflicts transactionally; checkpoint/truncate the WAL and compact the journal.
5. Disable Windows sign-in startup and close the app. The next launch generates a new device ID with tracking and alerts off.

Cloud records, exports saved elsewhere, backups and OS-maintained usage history/permissions are not deleted. New Android collection windows cannot backfill the previous account's system usage. Deleting SQLite rows is not a claim of forensic erasure from SSDs or external backups.

If reset fails, Lockin exposes only a closable recovery screen, not a half-reset account UI. Some steps may already have completed; close/reopen before retrying. No cloud deletion is attempted.

## Windows interruptions

A successful Windows tracking poll stores a local heartbeat, including polls that correctly observe lock/idle and count no activity. A gap longer than five seconds between successful checks records the latest interruption. It survives restart and successful later polls until acknowledged in Settings. Intentional Stop tracking clears the heartbeat rather than fabricating a crash gap. Older builds without a heartbeat cannot reconstruct earlier interruptions.

The notice reports a gap in confirmed tracking checks, not proof that every instant in it was active usage. No missing usage is estimated or uploaded. The approved Focus screen shows only a quiet pointer to Settings when a notice needs review.

## Verification

Targeted tests use real SQLite snapshots/close-reopen, public controller/Settings actions, and the real Supabase client against the existing loopback contract fixture. They cover secret exclusion, pending edits, reset confirmation/cancellation, sealed late auth writes, in-flight upload draining, fresh device identity, and persistent/dismissible interruption notices without invented activity. File-picker OS calls and live Supabase behavior are separate native/deployment checks; passing these tests does not establish those paths.
