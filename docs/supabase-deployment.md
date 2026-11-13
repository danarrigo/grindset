# Supabase deployment

## Project and client configuration

- Project: **lockin**, ref `fajonmibrspfdozldjap`.
- Region: Sydney, `ap-southeast-2`.
- API URL: `https://fajonmibrspfdozldjap.supabase.co`.
- Created in the owner's existing free organization after explicit approval of the quoted **$0/month** project cost.
- The public publishable key is configured in ignored `config.local.json` and the repository variable `SUPABASE_PUBLISHABLE_KEY`. `SUPABASE_URL` is configured alongside it. No service-role key is used by app builds.

Developer MCP URLs in ignored `.mcp.json` are configured with this project ref. The currently running adapter cached its earlier connection; reload Pi before relying on the narrower URL scope. Do not use this connection for unrelated projects.

## Applied migrations

Applied in order through the authenticated Supabase MCP migration tool:

| Repository source | Hosted migration version | Hosted name |
| --- | --- | --- |
| `202611100001_usage.sql` | `20261113004427` | `usage` |
| `202611110001_shared_state.sql` | `20261113004545` | `shared_state` |
| `202611130001_function_grants.sql` | `20261113005118` | `function_grants` |

MCP assigns deployment timestamps rather than preserving local filename versions. Before using CLI `db push`, reconcile the migration history with this mapping; do not blindly replay already-applied DDL. No application rows or Auth users were seeded by the deployment.

## Hosted privilege difference and fix

Hosted Supabase grants function EXECUTE directly to `anon` and `authenticated` by default. The original migrations revoked PUBLIC, which did not remove those direct grants. A public-key-only POST to `apply_shared_changes` initially reached its auth guard and returned HTTP 400 / `P0001`. The auth guard rejected it, but anonymous callers should not reach the security-definer function at all.

The third migration explicitly revokes direct grants, then grants only the intended RPC/source validator to `authenticated`. The local SQL bootstrap now reproduces the hosted defaults. The new grant assertion failed before this migration and passed afterward together with the existing two-user SQL/RLS suite.

After the live fix:

- The same anonymous HTTP RPC call returns **401 / `42501`, permission denied**.
- All five application tables have RLS enabled.
- Anonymous device reads and anonymous RPC execution are denied.
- Authenticated RPC execution is allowed; direct authenticated shared-state inserts are denied.
- Source validation accepts app identifiers/hosts and rejects executable paths and complete URLs.

Security advisors no longer report anonymous security-definer execution. Two no-policy informational findings are intentional for private `shared_heads`/`shared_receipts`; the authenticated security-definer warning reflects the intended owner-checked RPC. Do not silence those by granting direct table access or removing the RPC's ownership checks.

## Hosted client acceptance (2026-11-13)

`test/live_cloud_sync_test.dart` passed against this deployed project using three independent Supabase clients and file-backed SQLite journals: two for one account and one for a second account. This exercised:

- Real signup-token verification, email-confirmed Auth users, local sign-out and password login.
- Shared rules, source links, budgets, schedules, timezone, active session and early-finished history. Focus blocklists remained device-local.
- Confirmed usage uploads/downloads, overlapping-device interval union and upload acknowledgements.
- A transport-disabled offline edit, failed request, hosted conflict, explicit retry and convergence.
- Unfiltered second-account reads and a forged-owner write rejected with `42501`.
- Local reset, cloud-record preservation, another client's successful refresh, and a fresh local device identity with tracking/alerts off.

Two disposable accounts were provisioned through the supported server-side Auth signup-link API. The clients verified real confirmation tokens; no JWTs or Auth database rows were fabricated. The admin credential stayed in server-process memory, never in app builds or the temporary client credential file. Both test accounts, their cascading application rows and temporary credentials were removed afterward; all six inspected account/application counts returned zero. Email confirmation remained required.

The first hosted run exposed `FormatException: Shared sync revisions are not ordered.` Dart's PostgREST SDK defaults to descending order. Revision-keyset downloads now explicitly request ascending order. The loopback fixture was corrected to honor the requested sort; its existing 513-row pagination regression failed before the client fix and passed afterward. Earlier green CI/builds, including `5f3ac3c`, do not include this client fix.

To opt in, set `LOCKIN_LIVE_AUTH_FILE` to a private JSON file containing `url`, a public publishable `key`, and two `accounts` with `email`, `password`, `id` and a signup `token_hash` for an unconfirmed account. Emails must start with `lockin-acceptance-`; use empty disposable accounts only. Run `flutter test test/live_cloud_sync_test.dart`. Without that environment variable it is skipped. The test writes cloud data and does not provision/delete accounts; the operator must clean up only the accounts they created through a trusted server-side path. Never put an admin key in this file.

## Evidence limits

This is real hosted Auth/RLS/network acceptance through application controllers and storage, not two installed native devices. Inbox email delivery, normal account creation/confirmation through the installed UI, Windows/Android device-to-device acceptance and native scheduling remain separate checks. Auth settings were not weakened to manufacture a passing test.

The separately authorized paused `lotorix` project (`hoyilrdpusfezwcrbvoz`) was deleted through the supported Management API after checking its name, organization and inactive state. Deletion returned HTTP 200; a follow-up project read returned 404. The `lockin` project was not deleted.
