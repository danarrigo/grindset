-- AI unlock checks: one row per check, only to cap how many a person can run
-- a day (the DeepSeek key is billed per check). Reasons are never stored.
-- Written and read only by the unlock-check Edge Function's service role.
create table public.unlock_checks (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  checked_at timestamptz not null default now(),
  allowed boolean not null
);
create index unlock_checks_user_time on public.unlock_checks (user_id, checked_at);
alter table public.unlock_checks enable row level security;
revoke all on public.unlock_checks from public, anon, authenticated;
