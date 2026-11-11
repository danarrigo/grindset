-- Exercise actual PostgreSQL policies/RPCs with two fixture users. The Auth
-- boundary is provided by bootstrap.sql; live Supabase Auth is a separate test.
begin;
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
insert into public.devices(user_id,id,label,platform) values
 ('11111111-1111-4111-8111-111111111111','desktop','Desktop','Windows'),
 ('11111111-1111-4111-8111-111111111111','phone','Phone','Android');

do $$
declare
  first jsonb;
  replay jsonb;
  result jsonb;
  version bigint;
  denied boolean;
  change jsonb;
  session jsonb := jsonb_build_object('id','focus-a','phase','focus','started_at',now()-interval '10 seconds','ended_at',now()+interval '25 minutes','label','Deep work');
  malformed jsonb;
begin
  if public.valid_source('web:https://example.com/private') or public.valid_source('windows:C:\private\app.exe')
     or not public.valid_source('windows:some app.exe') or not public.valid_source('android:com.android.chrome') then raise exception 'Source privacy validation failed'; end if;
  denied := false;
  begin perform public.apply_shared_changes('desktop','[]','22222222-2222-4222-8222-222222222222'); exception when raise_exception then denied := sqlerrm='An authenticated device is required'; end;
  if not denied then raise exception 'A switched account rebound pending state'; end if;
  first := public.apply_shared_changes('desktop','[{"kind":"setting","id":"timezone","mutation_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","base_revision":0,"value":{"timezone":"UTC"}}]');
  if first->0->'applied' <> 'true'::jsonb then raise exception 'Initial timezone was not accepted'; end if;
  version := (first->0->'record'->>'revision')::bigint;
  perform public.apply_shared_changes('desktop',jsonb_build_array(jsonb_build_object('kind','setting','id','timezone','mutation_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2','base_revision',version,'value',jsonb_build_object('timezone','America/New_York'))));
  replay := public.apply_shared_changes('desktop','[{"kind":"setting","id":"timezone","mutation_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","base_revision":0,"value":{"timezone":"UTC"}}]');
  if replay<>first or (select value->>'timezone' from public.shared_state where kind='setting')<>'America/New_York' then raise exception 'A lost acknowledgement was not idempotent'; end if;

  change := '{"kind":"rule","id":"video","mutation_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3","base_revision":0,"value":{"id":"video","name":"Confirmed","sources":["web:example.com"],"daily_minutes":30,"schedules":[]}}';
  perform public.apply_shared_changes('desktop',jsonb_build_array(change));
  result := public.apply_shared_changes('phone',jsonb_build_array(jsonb_set(jsonb_set(change,'{mutation_id}','"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4"'),'{value,name}','"Offline edit"')));
  if result->0->'applied'<>'false'::jsonb or result->0->'record'->'value'->>'name'<>'Confirmed' then raise exception 'A stale edit overwrote confirmed policy'; end if;
  denied := false;
  begin
    perform public.apply_shared_changes('desktop',jsonb_build_array(jsonb_set(change,'{value,name}','"Mutated receipt"')));
  exception when raise_exception then denied := sqlerrm='Mutation identifiers are immutable'; end;
  if not denied then raise exception 'Mutation identity was mutable'; end if;

  result := public.apply_shared_changes('desktop',jsonb_build_array(jsonb_build_object('kind','focus','id','active','mutation_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5','base_revision',0,'value',session)));
  version := (result->0->'record'->>'revision')::bigint;
  result := public.apply_shared_changes('phone',jsonb_build_array(jsonb_build_object('kind','focus','id','active','mutation_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6','base_revision',version,'value',session || '{"id":"competing"}'::jsonb)));
  if result->0->'applied'<>'false'::jsonb or result->0->'record'->'value'->>'id'<>'focus-a' then raise exception 'A running shared focus was replaced'; end if;
  result := public.apply_shared_changes('desktop',jsonb_build_array(jsonb_build_object('kind','session','id','focus-a','mutation_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa7','base_revision',0,'value',session)));
  version := (result->0->'record'->>'revision')::bigint;
  result := public.apply_shared_changes('phone',jsonb_build_array(jsonb_build_object('kind','session','id','focus-a','mutation_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa8','base_revision',0,'value',session || jsonb_build_object('ended_at',now()))));
  if result->0->'applied'<>'true'::jsonb or (result->0->'record'->'value'->>'ended_at')::timestamptz>now() then raise exception 'Confirmed session history did not shorten safely'; end if;
  if (select (value->>'ended_at')::timestamptz from public.shared_state where kind='focus')>now() then raise exception 'Shortened history left the shared focus slot running'; end if;
  result := public.apply_shared_changes('desktop',jsonb_build_array(jsonb_build_object('kind','session','id','focus-a','mutation_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa9','base_revision',version,'value',session)));
  if (result->0->'record'->'value'->>'ended_at')::timestamptz>now() then raise exception 'A retry resurrected a finished session'; end if;

  for malformed in select value from jsonb_array_elements(jsonb_build_array(
    '{"id":"video","name":"Bad","sources":["web:https://example.com/private?q=secret"],"schedules":[]}'::jsonb,
    '{"id":"video","name":"Bad","sources":["web:example.com"],"schedules":[{"weekdays":[1],"end_minute":100}]}'::jsonb,
    '{"id":"video","name":"Bad","sources":["web:example.com"],"schedules":[{"weekdays":["1"],"start_minute":50,"end_minute":100}]}'::jsonb
  )) loop
    denied := false;
    begin perform public.validate_shared_value('rule','video',malformed); exception when others then denied := true; end;
    -- This helper is intentionally not directly callable by authenticated users.
    -- Exercise it through the authenticated RPC as well.
    begin
      perform public.apply_shared_changes('desktop',jsonb_build_array(jsonb_build_object('kind','rule','id','bad','mutation_id',gen_random_uuid(),'base_revision',0,'value',malformed || '{"id":"bad"}'::jsonb)));
      denied := false;
    exception when others then null; end;
    if not denied then raise exception 'Malformed rule was stored'; end if;
  end loop;
  denied := false;
  begin perform public.apply_shared_changes('desktop',jsonb_build_array(jsonb_build_object('kind','session','id','bad','mutation_id',gen_random_uuid(),'base_revision',0,'value',(session - 'phase') || '{"id":"bad"}'::jsonb))); exception when others then denied := true; end;
  if not denied then raise exception 'Missing session phase was accepted'; end if;
  denied := false;
  begin insert into public.shared_state values(auth.uid(),'setting','timezone',999,'{"timezone":"UTC"}','desktop'); exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Direct writes bypassed the revision protocol'; end if;
end;
$$;

-- A second authenticated user sees none of the first user's rows and cannot
-- use the first user's device as an authenticated mutation identity.
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
do $$
declare denied boolean := false;
begin
  if exists(select 1 from public.shared_state) or exists(select 1 from public.devices) then raise exception 'Cross-user read leak'; end if;
  begin perform public.apply_shared_changes('desktop','[]'); exception when raise_exception then denied := sqlerrm='An authenticated device is required'; end;
  if not denied then raise exception 'Cross-user device identity accepted'; end if;
  denied := false;
  begin insert into public.devices(user_id,id,label,platform) values('11111111-1111-4111-8111-111111111111','attack','Not mine','Windows'); exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Cross-user write leak'; end if;
end;
$$;
insert into public.devices(user_id,id,label,platform) values(auth.uid(),'desktop','Other owner','Windows');
select public.apply_shared_changes('desktop','[{"kind":"setting","id":"timezone","mutation_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1","base_revision":0,"value":{"timezone":"Asia/Tokyo"}}]');
reset role;
do $$ begin
  if (select count(*) from public.shared_state where kind='setting')<>2 then raise exception 'Owner-scoped singleton collision'; end if;
end $$;
rollback;
\echo 'Shared-state RPC, idempotency, conflict and two-user RLS checks passed.'
