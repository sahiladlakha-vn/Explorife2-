-- Fixes a bug in admin_create_user_profile's auto-generate-username branch
-- (20260925000200_admin_create_user_profile.sql): the one-argument form
-- extensions.unaccent(text) resolves its dictionary ('unaccent') by NAME,
-- looked up via the search_path in effect when the *dictionary lookup*
-- runs — and this function pins search_path to 'public' only (line 34 of
-- that migration), which doesn't include 'extensions'. So a real call
-- down the auto-generate branch (e.g. a "New User" invite with no
-- explicit username) would raise
--   text search dictionary "unaccent" does not exist
-- rather than actually folding accents. Test 1 of the prior smoke test
-- never exercised this branch (it targeted an existing confirmed user
-- and hit not_a_pending_invite first), so this shipped unnoticed.
--
-- Fixed via the two-argument form, which takes the dictionary as a
-- regdictionary OID rather than resolving a bare name at call time — the
-- cast 'extensions.unaccent'::regdictionary is schema-qualified in the
-- string itself, so it resolves correctly regardless of search_path.
-- Only this one expression changes; everything else in the function body
-- (guards, username disambiguation loop, role/audit-log writes) is
-- untouched.
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
      lower(extensions.unaccent(
        'extensions.unaccent'::regdictionary,
        coalesce(p_full_name, '')
      )),
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

-- create or replace preserves the existing grants/ACL (unlike the
-- drop+create the invite-status migration needed for a return-type
-- change), so no grant restoration is required here — confirmed this
-- function's signature and return type are unchanged from
-- 20260925000200_admin_create_user_profile.sql.
