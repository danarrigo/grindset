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

## Evidence limits

This establishes real project/schema deployment, public configuration, server-side grant inspection and anonymous HTTP denial. It does **not** establish successful user sign-up/email delivery, signed-in Auth/RLS behavior, two-device synchronization or offline reconciliation against deployed Supabase. The prior fixture-based PostgreSQL/HTTP suites remain separately labeled.

Create/confirm a real app account through the app before live signed-in acceptance. Auth email delivery/settings belong to this project; they were not weakened to manufacture a passing login test.
