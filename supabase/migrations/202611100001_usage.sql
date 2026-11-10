-- Usage-only checkpoint. Session, rule and account-timezone sync follow separately.
-- Run in your own Supabase project. Never embed a service-role key in clients.
begin;

create table public.devices (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  label text not null check (length(label) between 1 and 120),
  platform text not null check (platform in ('Windows', 'Android')),
  last_seen_at timestamptz not null default now(),
  primary key (user_id, id)
);

create table public.usage_intervals (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  device_id text not null,
  source text not null check (length(source) between 1 and 512),
  started_at timestamptz not null,
  ended_at timestamptz not null,
  primary key (user_id, id),
  foreign key (user_id, device_id) references public.devices(user_id, id) on delete cascade,
  check (ended_at > started_at)
);
create index usage_intervals_user_time on public.usage_intervals(user_id, ended_at);

create function public.touch_device() returns trigger language plpgsql
set search_path = '' as $$
begin
  new.last_seen_at := pg_catalog.clock_timestamp();
  return new;
end;
$$;
create trigger devices_touch before insert or update on public.devices
  for each row execute function public.touch_device();

-- Retried or stale uploads may extend an interval, but never shorten it or
-- silently reassign its device/source/start. Client upload acknowledgements
-- similarly must not clear a newer pending local observation.
create function public.preserve_usage_identity() returns trigger language plpgsql
set search_path = '' as $$
begin
  if new.device_id <> old.device_id or new.source <> old.source
     or new.started_at <> old.started_at then
    raise exception 'Usage interval identity is immutable';
  end if;
  new.ended_at := greatest(new.ended_at, old.ended_at);
  return new;
end;
$$;
create trigger usage_preserve before update on public.usage_intervals
  for each row execute function public.preserve_usage_identity();

alter table public.devices enable row level security;
alter table public.usage_intervals enable row level security;
create policy owner_only on public.devices for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy owner_only on public.usage_intervals for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
revoke all on public.devices, public.usage_intervals from anon, public;
grant select, insert, update, delete on public.devices, public.usage_intervals to authenticated;
revoke all on function public.touch_device(), public.preserve_usage_identity() from public;
commit;
