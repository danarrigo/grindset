-- Focus hours: one shared schedule during which every rule that blocks while
-- focusing is on. Stored as setting 'focus_hours' = {"schedules": [...]} and
-- validated exactly like a rule's schedules.
create function public.validate_schedules(schedules jsonb) returns void
language plpgsql set search_path = '' as $$
declare
  item jsonb;
begin
    for item in select * from pg_catalog.jsonb_array_elements(schedules) loop
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
end;
$$;
revoke all on function public.validate_schedules(jsonb) from public, anon, authenticated;

create or replace function public.validate_shared_value(kind text, entity_id text, value jsonb) returns void
language plpgsql set search_path = '' as $$
declare
  item jsonb;
  source text;
  started timestamptz;
  ended timestamptz;
begin
  if kind is null or kind not in ('rule','setting','focus','session') then raise exception 'Unknown shared entity'; end if;
  if (kind='focus' and entity_id<>'active') or (kind='setting' and entity_id not in ('timezone','focus_hours')) then raise exception 'Invalid singleton identifier'; end if;
  if value is null then
    if kind='setting' then raise exception 'Account settings cannot be deleted'; end if;
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
    perform public.validate_schedules(value->'schedules');
  elsif kind='setting' and entity_id='focus_hours' then
    if value - array['schedules'] <> '{}'::jsonb
       or pg_catalog.jsonb_typeof(value->'schedules') is distinct from 'array'
       or pg_catalog.jsonb_array_length(value->'schedules') > 64 then raise exception 'Invalid Focus hours'; end if;
    perform public.validate_schedules(value->'schedules');
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
