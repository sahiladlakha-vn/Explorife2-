-- unaccent, so a full name like "Nguyễn Minh" generates "nguyenminh" rather
-- than dropping the accented letters outright ("nguynminh"). Installed into
-- the dedicated `extensions` schema per Supabase convention, not `public`.
create extension if not exists unaccent with schema extensions;

-- Backs the Users page's "New User" flow's second step: once the Edge
-- Function's service-role client has created the auth.users row via
-- inviteUserByEmail (firing handle_new_user(), which gives a bare
-- role='traveler'/username=null profiles row), THIS function — called by
-- the Edge Function using the *caller's own JWT*, never the service role —
-- sets the real name/username/role and writes the audit entry. Using the
-- caller's JWT here (not the service role) is deliberate: auth.uid() must
-- resolve to the real Super Admin so is_super_admin() below, the existing
-- profiles_lock_role_field trigger, and the audit log's actor_id all see
-- who really did this — with the service role, auth.uid() is null and the
-- role assignment would be reverted by the lock trigger (or rejected here).
--
-- Deliberately restricted to a *freshly invited* account (see the
-- auth.users guard below): without it, a Super Admin could call this on any
-- existing user — including one who signed up normally — and bypass every
-- check admin_update_user_role enforces (self-demotion guard, last-
-- super_admin guard, anonymous-session guard), since this function has none
-- of those. The guard makes that impossible: it only ever touches a row
-- auth.users itself confirms nobody has signed into yet.
create or replace function public.admin_create_user_profile(
  p_user_id uuid,
  p_full_name text,
  p_username text,
  p_role public.user_role
)
returns public.profiles
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_profile public.profiles;
  v_auth_user record;
  v_base text;
  v_candidate text;
  v_suffix int := 0;
begin
  if not public.is_super_admin() then
    raise exception 'insufficient_privilege: only a super_admin may create a user';
  end if;

  select id, invited_at, email_confirmed_at, last_sign_in_at, created_at,
         coalesce(is_anonymous, false) as is_anonymous
    into v_auth_user
  from auth.users
  where id = p_user_id;

  if v_auth_user.id is null then
    raise exception 'profile not found for %; the invite may not have completed', p_user_id;
  end if;

  if v_auth_user.invited_at is null
     or v_auth_user.email_confirmed_at is not null
     or v_auth_user.last_sign_in_at is not null
     or v_auth_user.is_anonymous
     or v_auth_user.created_at < now() - interval '10 minutes' then
    raise exception 'not_a_pending_invite: % is not a freshly invited, unconfirmed account', p_user_id;
  end if;

  update public.profiles
  set display_name = coalesce(nullif(btrim(p_full_name), ''), display_name),
      name = coalesce(nullif(btrim(p_full_name), ''), name)
  where id = p_user_id;

  if p_username is not null and btrim(p_username) <> '' then
    begin
      update public.profiles set username = lower(btrim(p_username)) where id = p_user_id;
    exception
      when unique_violation then
        raise exception 'username_taken: that username is already taken';
      when check_violation then
        raise exception 'username_invalid: usernames are 3-20 lowercase letters, numbers, or underscores';
    end;
  else
    -- Derive from the full name (accent-folded), disambiguate with
    -- _1, _2, ... Each candidate is a real UPDATE attempt; a
    -- unique_violation is caught and just advances the suffix — safe
    -- against two concurrent invites because the unique index (not a
    -- preceding SELECT) is the arbiter, not a check-then-write race.
    v_base := regexp_replace(
      lower(extensions.unaccent(coalesce(p_full_name, ''))),
      '[^a-z0-9]', '', 'g'
    );
    if length(v_base) < 3 then
      v_base := 'user';
    end if;
    v_base := left(v_base, 16);

    loop
      v_candidate := case when v_suffix = 0 then v_base else v_base || '_' || v_suffix end;
      begin
        update public.profiles set username = v_candidate where id = p_user_id;
        exit;
      exception when unique_violation then
        v_suffix := v_suffix + 1;
        if v_suffix > 200 then
          raise exception 'could not generate a unique username for %', p_full_name;
        end if;
      end;
    end loop;
  end if;

  update public.profiles set role = p_role where id = p_user_id;

  insert into public.admin_action_log (actor_id, action_type, target_profile_id, old_role, new_role, details)
  values (auth.uid(), 'create_user', p_user_id, null, p_role, jsonb_build_object('full_name', p_full_name));

  select * into v_profile from public.profiles where id = p_user_id;
  return v_profile;
end;
$$;

-- New functions default to EXECUTE granted to PUBLIC *and* (Supabase's own
-- project bootstrap ALTER DEFAULT PRIVILEGES) an explicit direct grant to
-- anon/authenticated/service_role — confirmed live on admin_list_users,
-- which still has anon in its ACL despite nobody ever running a REVOKE.
-- `revoke ... from public` alone does NOT remove that separate direct
-- anon grant, so both are revoked explicitly here.
revoke execute on function public.admin_create_user_profile from public;
revoke execute on function public.admin_create_user_profile from anon;
grant execute on function public.admin_create_user_profile to authenticated, service_role;

-- Server-side backstop for the Edge Function's own "still pending" check
-- (which looks up auth.users directly via the service-role admin API
-- before ever calling this) — this function re-checks independently of
-- what the Edge Function already verified, same "never trust the caller,
-- recheck here too" convention as admin_create_user_profile above and
-- admin_update_user_role.
create or replace function public.admin_log_resend_invite(p_target_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_invited_at timestamptz;
  v_email_confirmed_at timestamptz;
begin
  if not public.is_super_admin() then
    raise exception 'insufficient_privilege: only a super_admin may resend an invite';
  end if;

  select invited_at, email_confirmed_at into v_invited_at, v_email_confirmed_at
  from auth.users where id = p_target_id;

  if v_invited_at is null or v_email_confirmed_at is not null then
    raise exception 'not_a_pending_invite: % is not a pending invite', p_target_id;
  end if;

  insert into public.admin_action_log (actor_id, action_type, target_profile_id)
  values (auth.uid(), 'resend_invite', p_target_id);
end;
$$;

revoke execute on function public.admin_log_resend_invite from public;
revoke execute on function public.admin_log_resend_invite from anon;
grant execute on function public.admin_log_resend_invite to authenticated, service_role;
