-- Narrow write path for the Google Sheets → Discovery sync. Callable with
-- just the anon key (same one already shipped in the compiled web app) —
-- SECURITY DEFINER lets it write despite RLS, but its own logic hardcodes
-- the owner and validates category, so the capability it actually exposes
-- to an anon caller is exactly "upsert one gem owned by this one account",
-- never anything broader. Deliberately not using the service_role key here:
-- that key bypasses RLS for the whole database and has no place inside a
-- Google Apps Script.
--
-- p_gem_id: pass an existing gem's id to update it (and it must already be
-- owned by the hardcoded account below, or the update silently matches
-- nothing and falls through to insert); pass null for a brand new gem.
-- Returns the gem's id either way, so the caller (Apps Script) can cache it
-- for the next sync and turn future edits of that row into updates instead
-- of new inserts.
create or replace function public.upsert_gem_from_sheet(
  p_gem_id uuid,
  p_gem_name text,
  p_gem_location text,
  p_category text,
  p_lat double precision,
  p_lng double precision,
  p_tagline text,
  p_description text,
  p_difficulty text,
  p_best_time_to_visit text,
  p_photo_url text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  -- Every gem this function ever writes is attributed to this account —
  -- sahil@durrowjones.com's account, per the earlier "attribute to my own
  -- account" decision for sheet-sourced gems. Not a parameter: an anon
  -- caller has no session to derive an owner from, and accepting an
  -- arbitrary owner id as input would let any caller attribute gems to
  -- someone else's account.
  v_owner uuid := '0f513f84-c0d2-4718-94f0-1f9fbfa1f3ef';
  v_id uuid;
  v_coords jsonb;
begin
  if p_gem_name is null or btrim(p_gem_name) = '' then
    raise exception 'gem_name is required';
  end if;

  if p_category is not null and btrim(p_category) <> '' and p_category not in (
    'hiking', 'camping', 'viewpoint', 'food', 'temple', 'cave', 'coastal', 'nature'
  ) then
    raise exception 'invalid category: %', p_category;
  end if;

  v_coords := case when p_lat is not null and p_lng is not null
    then jsonb_build_object('lat', p_lat, 'lng', p_lng)
    else null
  end;

  if p_gem_id is not null then
    update public.saved_gems
    set gem_name = p_gem_name,
        gem_location = nullif(btrim(p_gem_location), ''),
        category = nullif(btrim(p_category), ''),
        gem_coords = coalesce(v_coords, gem_coords),
        tagline = nullif(btrim(p_tagline), ''),
        description = nullif(btrim(p_description), ''),
        difficulty = nullif(btrim(p_difficulty), ''),
        best_time_to_visit = nullif(btrim(p_best_time_to_visit), ''),
        photo_url = coalesce(nullif(btrim(p_photo_url), ''), photo_url)
    where id = p_gem_id and user_id = v_owner
    returning id into v_id;
  end if;

  if v_id is null then
    insert into public.saved_gems (
      gem_name, gem_location, category, gem_coords,
      tagline, description, difficulty, best_time_to_visit, photo_url, user_id
    ) values (
      p_gem_name,
      nullif(btrim(p_gem_location), ''),
      nullif(btrim(p_category), ''),
      v_coords,
      nullif(btrim(p_tagline), ''),
      nullif(btrim(p_description), ''),
      nullif(btrim(p_difficulty), ''),
      nullif(btrim(p_best_time_to_visit), ''),
      nullif(btrim(p_photo_url), ''),
      v_owner
    )
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

-- PostgREST auto-exposes this at POST /rest/v1/rpc/upsert_gem_from_sheet.
-- Anon-callable by design (see the comment above) — nothing more permissive
-- than what's already true of every other anon-key call the app itself makes.
grant execute on function public.upsert_gem_from_sheet(
  uuid, text, text, text, double precision, double precision, text, text, text, text, text
) to anon;
