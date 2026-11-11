-- Shared rules, one account timezone and one active focus slot.
-- Mutations are owner-scoped, idempotent and compare-and-set, not client-clock LWW.
begin;

create table public.shared_heads (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 0
);
create table public.shared_state (
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('rule','setting','focus','session')),
  id text not null check (length(id) between 1 and 200),
  revision bigint not null check (revision > 0),
  value jsonb,
  updated_by text not null,
  primary key (user_id,kind,id),
  unique (user_id,revision)
);
create table public.shared_receipts (
  user_id uuid not null references auth.users(id) on delete cascade,
  mutation_id uuid not null,
  request jsonb not null,
  response jsonb not null,
  primary key(user_id,mutation_id)
);

create function public.valid_source(source text) returns boolean
language sql immutable strict set search_path = '' as $$
  select length(source) <= 512 and case
    when source like 'android:%' then source ~ '^android:[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$'
    when source like 'windows:%' then source ~ '^windows:[^/\\:\x00-\x1f]+\.exe$'
    when source like 'web:%' then
      length(substring(source from 5)) between 1 and 253
      and not exists (
        select 1 from pg_catalog.unnest(pg_catalog.string_to_array(pg_catalog.rtrim(pg_catalog.lower(substring(source from 5)),'.'),'.')) as label
        where label !~ '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$'
      )
    else false end;
$$;
alter table public.usage_intervals add constraint usage_source_identifier check (public.valid_source(source));

create function public.validate_shared_value(kind text, entity_id text, value jsonb) returns void
language plpgsql set search_path = '' as $$
declare
  item jsonb;
  source text;
  started timestamptz;
  ended timestamptz;
begin
  if kind is null or kind not in ('rule','setting','focus','session') then raise exception 'Unknown shared entity'; end if;
  if (kind='focus' and entity_id<>'active') or (kind='setting' and entity_id<>'timezone') then raise exception 'Invalid singleton identifier'; end if;
  if value is null then
    if kind='setting' then raise exception 'Account timezone cannot be deleted'; end if;
    return;
  end if;
  if pg_catalog.jsonb_typeof(value)<>'object' then raise exception 'Expected a shared object'; end if;
  if kind='rule' then
    if value - array['id','name','sources','daily_minutes','schedules'] <> '{}'::jsonb
       or value->>'id' is distinct from entity_id
       or pg_catalog.jsonb_typeof(value->'name') is distinct from 'string'
       or length(pg_catalog.btrim(value->>'name')) not between 1 and 120
       or pg_catalog.jsonb_typeof(value->'sources') is distinct from 'array'
       or pg_catalog.jsonb_array_length(value->'sources') not between 1 and 256
       or pg_catalog.jsonb_typeof(value->'schedules') is distinct from 'array'
       or pg_catalog.jsonb_array_length(value->'schedules') > 64 then raise exception 'Invalid shared rule'; end if;
    for item in select * from pg_catalog.jsonb_array_elements(value->'sources') loop
      if pg_catalog.jsonb_typeof(item)<>'string' then raise exception 'Expected source identifiers'; end if;
      source := item #>> '{}';
      if not public.valid_source(source) then raise exception 'Sources must be app identifiers or hosts, never paths or complete URLs'; end if;
    end loop;
    if value->'daily_minutes' is not null and value->'daily_minutes'<>'null'::jsonb then
      if (value->>'daily_minutes') !~ '^[0-9]+$' or (value->>'daily_minutes')::integer not between 1 and 1440 then raise exception 'Invalid daily budget'; end if;
    end if;
    for item in select * from pg_catalog.jsonb_array_elements(value->'schedules') loop
      if pg_catalog.jsonb_typeof(item)<>'object' or item - array['weekdays','start_minute','end_minute'] <> '{}'::jsonb
         or pg_catalog.jsonb_typeof(item->'weekdays') is distinct from 'array'
         or pg_catalog.jsonb_array_length(item->'weekdays') not between 1 and 7
         or pg_catalog.jsonb_typeof(item->'start_minute') is distinct from 'number'
         or pg_catalog.jsonb_typeof(item->'end_minute') is distinct from 'number'
         or (item->>'start_minute') !~ '^[0-9]+$' or (item->>'end_minute') !~ '^[0-9]+$'
         or (item->>'start_minute')::integer not between 0 and 1439
         or (item->>'end_minute')::integer not between 0 and 1439
         or item->>'start_minute' = item->>'end_minute'
         or exists(select 1 from pg_catalog.jsonb_array_elements(item->'weekdays') as day where pg_catalog.jsonb_typeof(day)<>'number' or day::text !~ '^[1-7]$') then raise exception 'Invalid schedule'; end if;
    end loop;
  elsif kind='setting' then
    if value - array['timezone'] <> '{}'::jsonb or not exists(select 1 from pg_catalog.pg_timezone_names where name=value->>'timezone') then raise exception 'Choose an IANA account timezone'; end if;
  else
    if value - array['id','phase','started_at','ended_at','label'] <> '{}'::jsonb
       or pg_catalog.jsonb_typeof(value->'id') is distinct from 'string'
       or length(value->>'id') not between 1 and 200
       or (kind='session' and value->>'id' is distinct from entity_id)
       or pg_catalog.jsonb_typeof(value->'phase') is distinct from 'string'
       or value->>'phase' not in ('focus','rest')
       or pg_catalog.jsonb_typeof(value->'label') is distinct from 'string'
       or length(value->>'label') not between 1 and 120
       or pg_catalog.jsonb_typeof(value->'started_at') is distinct from 'string'
       or pg_catalog.jsonb_typeof(value->'ended_at') is distinct from 'string' then raise exception 'Invalid focus session'; end if;
    started := (value->>'started_at')::timestamptz;
    ended := (value->>'ended_at')::timestamptz;
    if ended <= started or ended > started + interval '24 hours' or started > pg_catalog.clock_timestamp() + interval '5 minutes' then raise exception 'Invalid session dates or device clock'; end if;
  end if;
end;
$$;

create function public.apply_shared_changes(p_device_id text, p_changes jsonb, p_expected_owner uuid default auth.uid()) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  owner uuid := auth.uid();
  change jsonb;
  nonce uuid;
  entity_kind text;
  entity_id text;
  expected bigint;
  incoming jsonb;
  current_row public.shared_state%rowtype;
  receipt public.shared_receipts%rowtype;
  applied boolean;
  version bigint;
  result jsonb;
  results jsonb := '[]'::jsonb;
begin
  if owner is null or owner is distinct from p_expected_owner or not exists(select 1 from public.devices where user_id=owner and id=p_device_id) then raise exception 'An authenticated device is required'; end if;
  if pg_catalog.jsonb_typeof(p_changes) is distinct from 'array' or pg_catalog.jsonb_array_length(p_changes)>100 then raise exception 'Choose at most 100 changes'; end if;
  insert into public.shared_heads(user_id) values(owner) on conflict do nothing;
  -- Revisions commit in account order, so keyset delta reads cannot skip an
  -- uncommitted lower revision. There is no cross-account global lock.
  perform 1 from public.shared_heads where user_id=owner for update;
  for change in select * from pg_catalog.jsonb_array_elements(p_changes) loop
    if pg_catalog.jsonb_typeof(change) is distinct from 'object'
       or change - array['kind','id','mutation_id','base_revision','value'] <> '{}'::jsonb
       or pg_catalog.jsonb_typeof(change->'kind') is distinct from 'string'
       or pg_catalog.jsonb_typeof(change->'id') is distinct from 'string'
       or pg_catalog.jsonb_typeof(change->'mutation_id') is distinct from 'string'
       or pg_catalog.jsonb_typeof(change->'base_revision') is distinct from 'number'
       or not (change ? 'value') or (change->>'base_revision') !~ '^[0-9]+$'
       or length(change->>'id') not between 1 and 200 then raise exception 'Invalid shared mutation'; end if;
    nonce := (change->>'mutation_id')::uuid;
    select * into receipt from public.shared_receipts where user_id=owner and mutation_id=nonce;
    if found then
      if receipt.request<>change then raise exception 'Mutation identifiers are immutable'; end if;
      results := results || pg_catalog.jsonb_build_array(receipt.response);
      continue;
    end if;
    entity_kind := change->>'kind'; entity_id := change->>'id'; expected := (change->>'base_revision')::bigint;
    incoming := nullif(change->'value','null'::jsonb);
    perform public.validate_shared_value(entity_kind, entity_id, incoming);
    select * into current_row from public.shared_state where user_id=owner and kind=entity_kind and id=entity_id;
    applied := coalesce(current_row.revision,0)=expected;
    -- History can only shorten a known session, not resurrect or extend it.
    if entity_kind='session' and current_row.value is not null and incoming is not null then
      if current_row.value->>'id' is distinct from incoming->>'id'
         or current_row.value->>'phase' is distinct from incoming->>'phase'
         or (current_row.value->>'started_at')::timestamptz<>(incoming->>'started_at')::timestamptz then raise exception 'Session identity is immutable'; end if;
      if (incoming->>'ended_at')::timestamptz >= (current_row.value->>'ended_at')::timestamptz then incoming := current_row.value; end if;
      applied := true;
    end if;
    if entity_kind='focus' and current_row.value is not null and incoming is not null then
      if current_row.value->>'id'=incoming->>'id' and (
          current_row.value->>'phase' is distinct from incoming->>'phase'
          or (current_row.value->>'started_at')::timestamptz<>(incoming->>'started_at')::timestamptz) then raise exception 'Session identity is immutable'; end if;
      if current_row.value->>'id'<>incoming->>'id' and (current_row.value->>'ended_at')::timestamptz>pg_catalog.clock_timestamp() then applied := false; end if;
      if current_row.value->>'id'=incoming->>'id' and (incoming->>'ended_at')::timestamptz>(current_row.value->>'ended_at')::timestamptz then applied := false; end if;
    end if;
    if applied and (current_row.revision is null or incoming is distinct from current_row.value) then
      update public.shared_heads set revision=revision+1 where user_id=owner returning revision into version;
      insert into public.shared_state(user_id,kind,id,revision,value,updated_by) values(owner,entity_kind,entity_id,version,incoming,p_device_id)
        on conflict(user_id,kind,id) do update set revision=excluded.revision,value=excluded.value,updated_by=excluded.updated_by
        returning * into current_row;
    elsif current_row.revision is null then raise exception 'The confirmed state is missing; do not reset local history silently'; end if;
    -- A confirmed early finish must also close the matching active slot, even
    -- when its separate focus acknowledgement raced another device's update.
    if applied and entity_kind='session' and incoming is not null and exists(
      select 1 from public.shared_state where user_id=owner and kind='focus' and id='active'
        and value->>'id'=entity_id and (value->>'ended_at')::timestamptz>(incoming->>'ended_at')::timestamptz
    ) then
      update public.shared_heads set revision=revision+1 where user_id=owner returning revision into version;
      update public.shared_state set revision=version,value=pg_catalog.jsonb_set(value,'{ended_at}',incoming->'ended_at'),updated_by=p_device_id
        where user_id=owner and kind='focus' and id='active';
    end if;
    result := pg_catalog.jsonb_build_object('mutation_id',nonce,'applied',applied,'record',pg_catalog.jsonb_build_object('kind',entity_kind,'id',entity_id,'revision',current_row.revision,'value',current_row.value));
    insert into public.shared_receipts(user_id,mutation_id,request,response) values(owner,nonce,change,result);
    results := results || pg_catalog.jsonb_build_array(result);
  end loop;
  return results;
end;
$$;

alter table public.shared_heads enable row level security;
alter table public.shared_state enable row level security;
alter table public.shared_receipts enable row level security;
create policy owner_read on public.shared_state for select to authenticated using ((select auth.uid())=user_id);
revoke all on public.shared_heads,public.shared_state,public.shared_receipts from public,anon,authenticated;
grant select on public.shared_state to authenticated;
revoke all on function public.apply_shared_changes(text,jsonb,uuid),public.validate_shared_value(text,text,jsonb) from public;
grant execute on function public.apply_shared_changes(text,jsonb,uuid) to authenticated;
-- The identifier check is also evaluated by ordinary usage inserts under RLS.
revoke all on function public.valid_source(text) from public;
grant execute on function public.valid_source(text) to authenticated;
commit;
