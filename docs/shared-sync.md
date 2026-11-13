# Shared account state

For a new project, apply all migrations in `supabase/migrations/` in filename order. The owner's project is already deployed; see [deployment history](supabase-deployment.md) before replaying DDL. Usage remains an append/extend-only confirmed interval journal. Shared rules, account timezone, active focus and timer history use a separate revisioned protocol. Public clients never receive an admin key.

## Offline and conflict behavior

Local changes and their SQLite outbox snapshot commit together. The outbox coalesces edits to each entity, retains a stable mutation ID across retries, and cannot acknowledge away an edit made during an older upload. Changes request a prompt sync; signed-in runtimes also poll every 30 seconds with failure backoff.

- Named activity rules and their source links, budgets and schedules are shared.
- Focus block toggles and five-minute overrides remain local to each device. A newly downloaded activity does not automatically join that device's focus blocklist.
- The first confirmed timezone initializes the account. Other devices adopt it. Explicit competing timezone edits are reviewed like rule edits.
- One confirmed active focus slot is authoritative. A second running session cannot replace it, even if a client knows its revision. Conflicting offline starts/ends adopt the confirmed slot and show an explanation. Elapsed local focus is retained and union-accounted; a losing zero-elapsed start is not fabricated into a positive interval.
- Session history has immutable identity and can only shorten a known end. A confirmed early finish also closes the matching active slot atomically. Replayed acknowledgements cannot resurrect finished timers.
- Stale rule/timezone edits never silently overwrite confirmed policy. Their full payloads remain in `sync_conflicts`. Settings shows both versions for review. **Use saved edit** is an explicit replacement against the revision shown in the dialog; another intervening edit can conflict again. **Keep confirmed** discards only the saved edit.
- Offline devices retain last-confirmed remote state; global budgets can overshoot before reconnection. Confirmed usage is never extrapolated through a disconnection.

## Server invariants

`apply_shared_changes` derives ownership from `auth.uid()` and requires an owner-scoped registered device. Authenticated clients can select their own shared records but cannot write tables directly. The RPC validates source identifiers and session/rule payloads; page paths, URLs and metadata are not accepted as usage sources.

Each account has its own serialized revision allocator. Revisions are assigned while holding the account row lock and commit in that order, making keyset delta reads safe against a lower uncommitted revision. There is no global cross-account lock. Tombstones preserve entity versions. Immutable mutation receipts make a lost acknowledgement idempotent even after another device edits the same item.

SQLite schema 2 adds canonical versions, a durable outbox and saved conflicts. Schema-one timers, intervals and settings migrate without deleting history. Local history stays bound to its first cloud owner; another account cannot upload it.

## Verification and limits

Dart tests exercise real controller/SQLite behavior and the real Supabase client against a loopback HTTP contract fixture, including two independent device databases, shared timer completion, device-local blocklists, paginated deltas, conflicts and newer-edit acknowledgement races.

`test/sql/bootstrap.sql` and `test/sql/shared_state.sql` apply the actual migrations and test idempotency, compare-and-set, payload rejection, history shortening, direct-write denial and two-user RLS against PostgreSQL 16. The Auth boundary in that local SQL suite is a fixture, not real Supabase Auth.

The owner's deployed project passed real Auth confirmation/password login, signed-in RLS, shared state/usage, transport-offline conflict recovery and local-only reset using independent clients and file-backed journals. Revision downloads explicitly request ascending order; the SDK's descending default was caught by the hosted test and is now covered by the sort-aware pagination fixture. A later installed Windows/Android-emulator run verified inbox confirmation, native password login, shared timezone/session/history/rules/budgets, device-local focus flags and confirmed Windows usage downloaded by Android. The default localhost confirmation redirect remains an onboarding defect, and physical-device reliability and installed offline-conflict acceptance remain unverified; see [deployment evidence and limits](supabase-deployment.md). Native background scheduling and distribution policies are separate from the database contract. Sync is not an instantaneous server push service. Receipt/history retention still requires a future operational policy; no records are automatically purged. Settings now provides private export and an explicit, local-only reset/sign-out/restart flow before another account can use this device. Reset drains in-flight uploads, so it does not claim to undo a request already accepted by the server. See [device data controls](data-controls.md).

For isolated Windows validation, pass `--data-dir=<owned test directory>` to the executable. This selects a separate local journal, not another cloud identity. Do not point it at a journal open in another process.
