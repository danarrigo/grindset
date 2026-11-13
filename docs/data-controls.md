# Device data and account switching

## Export

Settings > **Export data** creates a private JSON archive. Windows uses a save-file dialog; Android uses the system document picker, without broad storage permissions. Cancelling the picker changes no app data.

The archive is a consistent SQLite snapshot, then streamed off-thread in batches of at most 500 rows. It includes settings from an explicit allowlist, all confirmed/pending intervals, timer history, canonical shared state, pending offline edits and saved conflicts. The live database is not held open while the user chooses a destination. Private temporary snapshot/output directories are removed afterward.

Format `lockin-export`, version `1`, records the UTC export time and SQLite schema version. Table rows retain their stored fields; interval timestamps are UTC epoch milliseconds. JSON-valued table fields/settings remain JSON strings. Auth credentials, browser pairing tokens and unknown future settings are excluded. Device/account identifiers and activity timestamps are personal data: the archive is not anonymous and should be stored securely. There is no automatic archive-import feature.

## Sign-out and another account

Sign-out keeps history and its original account binding. Another account cannot upload or adopt that journal. The login UI signs the mismatched account back out and directs the user to export/reset first; the sync protocol independently refuses mismatched owners before uploads.

To change accounts: export anything worth retaining, choose **Reset this device**, confirm **Reset and close**, reopen Lockin, and sign in to the other account. This is deliberately a restart, not a hot swap of SQLite/auth ownership.

## Reset

A file-backed runtime holds an OS lock for its journal until SQLite closes. A second Windows instance using the same folder cannot keep writing behind a reset; it receives a closable startup error directing the user to the existing tray app. The lock is released by the OS if the process dies, rather than treating an existing sidecar file as a live owner.

Reset affects this device only:

1. Stop polling and tracking, wait for the current observation, cancel scheduled completion alerts, rotate browser credentials and drain/close browser requests.
2. Stop automatic sync and await outstanding requests. An already-sent upload may have reached the account; reset is not a cloud deletion operation.
3. Sign out locally. Remote logout is best-effort when offline; other devices are not signed out. Auth persistence is serialized and sealed so a delayed refresh cannot restore the session after reset.
4. Delete local settings, history, account binding, revisions, pending edits and conflicts transactionally; checkpoint/truncate the WAL and compact the journal.
5. Disable Windows sign-in startup for the normal installation and close the app. A `--data-dir` preview preserves the installation's startup entry instead. The next launch generates a new device ID with tracking and alerts off.

Cloud records, exports saved elsewhere, backups and OS-maintained usage history/permissions are not deleted. New Android collection windows cannot backfill the previous account's system usage. Deleting SQLite rows is not a claim of forensic erasure from SSDs or external backups.

If reset fails, Lockin exposes only a closable recovery screen, not a half-reset account UI. Some steps may already have completed; close/reopen before retrying. No cloud deletion is attempted.

## Windows interruptions

A successful Windows tracking poll stores a local heartbeat, including polls that correctly observe lock/idle and count no activity. A gap longer than five seconds between successful checks records the latest interruption. It survives restart and successful later polls until acknowledged in Settings. Intentional Stop tracking clears the heartbeat rather than fabricating a crash gap. Older builds without a heartbeat cannot reconstruct earlier interruptions.

The notice reports a gap in confirmed tracking checks, not proof that every instant in it was active usage. No missing usage is estimated or uploaded. The approved Focus screen shows only a quiet pointer to Settings when a notice needs review.

## Verification

Targeted tests use real SQLite snapshots/close-reopen, public controller/Settings actions, and the real Supabase client against the existing loopback contract fixture. They cover secret exclusion, pending edits, reset confirmation/cancellation, sealed late auth writes, in-flight upload draining, fresh device identity, and persistent/dismissible interruption notices without invented activity. File-picker OS calls and live Supabase behavior are separate native/deployment checks; passing these tests does not establish those paths.

On 2026-11-13, native Windows checks used the isolated local-mode `b31a5dc` bundle (the same export/reset implementation as `5f3ac3c`). The real save dialog was opened/cancelled; the operator then saved an archive through that dialog in Documents. Its device ID matched the owned test journal, both timer-history rows were present, and auth/pairing settings and token values were absent. Cancelling native reset preserved identity/history. Confirming reset closed the process and emptied all six local tables; reopening generated a different device ID with no history and tracking/alerts off. The saved Documents archive remained intact. The initial ten-second process-exit check was too short; closure and empty tables were confirmed afterward, not an instant-reset guarantee.

A later native `4791d85` tracking run displayed a persistent Settings notice for the gap `08:31:00` to `08:31:12 UTC` on 2026-11-13. After Defender terminated the process, that notice remained in its SQLite journal; no interval overlapped the interior `08:31:01` to `08:31:11 UTC`. This verifies native notice display and durable storage without estimating the gap, not native restart/dismissal acceptance. The executable was quarantined before those remaining checks; see [the Defender blocker](packaging.md#defender-acceptance-blocker-2026-11-13).

On the dedicated API 36.1 AVD, installed `14b597f` opened the actual Android document picker and saved a `lockin-export` version-1 JSON archive in Downloads. The archive contained both shared session records and 49 confirmed intervals; auth and browser pairing credentials were excluded. The native reset dialog was cancelled, reopened and explicitly confirmed. Android returned to the launcher, and an independent snapshot found zero rows in all six local tables. The private export remained available. This establishes Android picker/export and local reset, not post-reset native redownload or physical-device behavior.

The hosted-client test separately verified local sign-out, cloud preservation and another client's successful token refresh after reset. That does not establish signed-in native Windows reset, native Android redownload after reset or physical-device behavior; those remain separate acceptance checks.
