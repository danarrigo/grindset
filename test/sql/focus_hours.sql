-- Focus hours sync as one shared setting with validated schedule windows.
do $$ begin
  if has_function_privilege('authenticated','public.validate_schedules(jsonb)','EXECUTE')
     or has_function_privilege('anon','public.validate_schedules(jsonb)','EXECUTE') then
    raise exception 'The schedule helper is callable directly';
  end if;
end $$;
begin;
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
insert into public.devices(user_id,id,label,platform) values(auth.uid(),'pc','PC','Windows');
do $$
declare
  result jsonb;
  denied boolean;
  bad jsonb;
begin
  result := public.apply_shared_changes('pc','[{"kind":"setting","id":"focus_hours","mutation_id":"dddddddd-dddd-4ddd-8ddd-ddddddddddd1","base_revision":0,"value":{"schedules":[{"weekdays":[1,2,3,4,5],"start_minute":540,"end_minute":1020}]}}]');
  if result->0->'applied'<>'true'::jsonb then raise exception 'Focus hours were not accepted'; end if;
  result := public.apply_shared_changes('pc',jsonb_build_array(jsonb_build_object('kind','setting','id','focus_hours','mutation_id','dddddddd-dddd-4ddd-8ddd-ddddddddddd2','base_revision',(result->0->'record'->>'revision')::bigint,'value','{"schedules":[]}'::jsonb)));
  if result->0->'applied'<>'true'::jsonb or (select jsonb_array_length(value->'schedules') from public.shared_state where kind='setting' and id='focus_hours')<>0 then raise exception 'Turning Focus hours off was not saved'; end if;
  result := public.apply_shared_changes('pc',jsonb_build_array(jsonb_build_object('kind','setting','id','focus_hours','mutation_id','dddddddd-dddd-4ddd-8ddd-ddddddddddd4','base_revision',(result->0->'record'->>'revision')::bigint,'value','{"schedules":[],"saved":[{"weekdays":[6],"start_minute":780,"end_minute":900}]}'::jsonb)));
  if result->0->'applied'<>'true'::jsonb then raise exception 'Saved Focus hours were not accepted'; end if;
  foreach bad in array array[
    '{"schedules":[{"weekdays":[8],"start_minute":540,"end_minute":1020}]}',
    '{"schedules":[{"weekdays":[1],"start_minute":540,"end_minute":540}]}',
    '{"schedules":[],"sources":["web:example.com"]}',
    '{"schedules":"weekdays"}',
    '{"schedules":[],"saved":{"weekdays":[1]}}',
    '{"schedules":[],"saved":[{"weekdays":[0],"start_minute":0,"end_minute":60}]}',
    'null'
  ]::jsonb[] loop
    denied := false;
    begin
      perform public.apply_shared_changes('pc',jsonb_build_array(jsonb_build_object('kind','setting','id','focus_hours','mutation_id',gen_random_uuid(),'base_revision',3,'value',case when bad='null'::jsonb then null else bad end)));
    exception when raise_exception then denied := true; end;
    if not denied then raise exception 'Invalid Focus hours were accepted: %', bad; end if;
  end loop;
  denied := false;
  begin
    perform public.apply_shared_changes('pc','[{"kind":"setting","id":"bedtime","mutation_id":"dddddddd-dddd-4ddd-8ddd-ddddddddddd3","base_revision":0,"value":{"schedules":[]}}]');
  exception when raise_exception then denied := true; end;
  if not denied then raise exception 'An unknown setting was accepted'; end if;
end;
$$;
rollback;
\echo 'Focus hours checks passed.'
