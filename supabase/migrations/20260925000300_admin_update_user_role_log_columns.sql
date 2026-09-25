-- Identical to the live admin_update_user_role except the final insert now
-- also populates the typed old_role/new_role columns added in the previous
-- migration (kept in `details` too, unchanged, for anything already reading
-- that jsonb shape). Every existing check — insufficient_privilege,
-- profile-not-found, anonymous-session guard, no-op same-role return, and
-- the last-super_admin guard — is untouched, byte-for-byte.
create or replace function public.admin_update_user_role(p_target_id uuid, p_new_role user_role)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_old_role public.user_role;
  v_is_anonymous boolean;
begin
  if not public.is_super_admin() then
    raise exception 'insufficient_privilege: only a super_admin may change another account''s role';
  end if;

  select pr.role, coalesce(au.is_anonymous, false)
    into v_old_role, v_is_anonymous
  from public.profiles pr
  join auth.users au on au.id = pr.id
  where pr.id = p_target_id;

  if v_old_role is null then
    raise exception 'profile not found: %', p_target_id;
  end if;

  if v_is_anonymous then
    raise exception 'cannot assign a role to an anonymous guest session';
  end if;

  if v_old_role = p_new_role then
    return;
  end if;

  if p_target_id = auth.uid()
     and p_new_role <> 'super_admin'::user_role
     and (select count(*) from public.profiles where role = 'super_admin'::user_role) <= 1 then
    raise exception 'cannot remove the last super_admin account''s super_admin role';
  end if;

  update public.profiles
  set role = p_new_role, updated_at = now()
  where id = p_target_id;

  insert into public.admin_action_log (actor_id, action_type, target_profile_id, old_role, new_role, details)
  values (
    auth.uid(), 'assign_role', p_target_id, v_old_role, p_new_role,
    jsonb_build_object('old_role', v_old_role, 'new_role', p_new_role)
  );
end;
$function$;

-- CREATE OR REPLACE preserves this function's existing ACL (already
-- correctly anon-free live), but made explicit here so all four
-- new/recreated functions in this feature follow the same visible,
-- self-documenting grant pattern rather than relying on that preservation
-- behavior implicitly.
revoke execute on function public.admin_update_user_role from public;
revoke execute on function public.admin_update_user_role from anon;
grant execute on function public.admin_update_user_role to authenticated, service_role;
