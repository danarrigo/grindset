-- Lets a signed-in person delete their own account. Every application table
-- references auth.users with ON DELETE CASCADE, so removing the Auth user
-- removes their devices, usage, shared state and receipts with it.
begin;
create function public.delete_account() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to delete your account' using errcode = '42501';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;
revoke all on function public.delete_account() from public, anon, authenticated;
grant execute on function public.delete_account() to authenticated;
commit;
