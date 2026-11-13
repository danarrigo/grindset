-- Hosted Supabase defaults grant EXECUTE directly to anon/authenticated.
-- Revoking only PUBLIC does not remove those role-specific grants.
begin;
revoke all on function public.touch_device(), public.preserve_usage_identity(),
  public.validate_shared_value(text,text,jsonb) from public,anon,authenticated;
revoke all on function public.apply_shared_changes(text,jsonb,uuid),
  public.valid_source(text) from public,anon,authenticated;
grant execute on function public.apply_shared_changes(text,jsonb,uuid),
  public.valid_source(text) to authenticated;
commit;
