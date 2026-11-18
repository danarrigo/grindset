-- Account deletion removes only the caller's account and everything it owns.
do $$ begin
  if has_function_privilege('anon','public.delete_account()','EXECUTE') then
    raise exception 'Anonymous callers can delete accounts';
  end if;
end $$;
begin;
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
insert into public.devices(user_id,id,label,platform) values(auth.uid(),'mine','Mine','Android');
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
insert into public.devices(user_id,id,label,platform) values(auth.uid(),'theirs','Theirs','Windows');
select public.apply_shared_changes('theirs','[{"kind":"setting","id":"timezone","mutation_id":"cccccccc-cccc-4ccc-8ccc-ccccccccccc1","base_revision":0,"value":{"timezone":"UTC"}}]');
select public.delete_account();
select set_config('request.jwt.claim.sub','',false);
do $$ declare denied boolean := false; begin
  begin perform public.delete_account(); exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Deletion without a signed-in user was allowed'; end if;
end $$;
reset role;
do $$ begin
  if exists(select 1 from auth.users where id='22222222-2222-4222-8222-222222222222')
     or exists(select 1 from public.devices where user_id='22222222-2222-4222-8222-222222222222')
     or exists(select 1 from public.shared_state where user_id='22222222-2222-4222-8222-222222222222')
     or exists(select 1 from public.shared_heads where user_id='22222222-2222-4222-8222-222222222222') then
    raise exception 'Deleted account left data behind';
  end if;
  if not exists(select 1 from public.devices where user_id='11111111-1111-4111-8111-111111111111') then
    raise exception 'Deleting one account removed another';
  end if;
end $$;
rollback;
\echo 'Account deletion checks passed.'
