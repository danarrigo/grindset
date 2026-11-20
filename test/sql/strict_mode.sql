-- Strict mode syncs as one shared on/off setting.
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
  result := public.apply_shared_changes('pc','[{"kind":"setting","id":"strict_mode","mutation_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1","base_revision":0,"value":{"enabled":true}}]');
  if result->0->'applied'<>'true'::jsonb then raise exception 'Strict mode was not accepted'; end if;
  foreach bad in array array['{"enabled":"yes"}','{"enabled":true,"until":"never"}','{}','null']::jsonb[] loop
    denied := false;
    begin
      perform public.apply_shared_changes('pc',jsonb_build_array(jsonb_build_object('kind','setting','id','strict_mode','mutation_id',gen_random_uuid(),'base_revision',1,'value',case when bad='null'::jsonb then null else bad end)));
    exception when raise_exception then denied := true; end;
    if not denied then raise exception 'Invalid strict mode was accepted: %', bad; end if;
  end loop;
end;
$$;
rollback;
\echo 'Strict mode checks passed.'
