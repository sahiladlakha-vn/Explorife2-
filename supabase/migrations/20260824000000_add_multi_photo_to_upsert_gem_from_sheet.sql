-- Extends upsert_gem_from_sheet (see 20260816000000) to accept multiple
-- photos, for the sheet's comma-separated Photo URL/Photo Filename columns —
-- feeds the same `photo_urls` array the app's own multi-photo gallery
-- already reads (see lib/models/gem.dart's Gem.allPhotos, added for the gem
-- detail screen's "4 of 12" gallery).
--
-- p_photo_urls is a NEW trailing parameter with a default, added via CREATE
-- OR REPLACE rather than DROP+CREATE — this keeps the same function OID, so
-- the existing `grant execute ... to anon` from the original migration still
-- applies with no new grant needed, and any caller still passing only the
-- original 11 arguments (none currently do outside this repo, but
-- defensively) keeps working unchanged.
--
-- p_photo_url stays the "cover" photo (first in the list) for every reader
-- that only knows about a single photo_url column — exactly the convention
-- the app's own GemRepository.create()/GemProvider.publish() already use.
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
  p_photo_url text,
  p_photo_urls text[] default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := '0f513f84-c0d2-4718-94f0-1f9fbfa1f3ef';
  v_id uuid;
  v_coords jsonb;
  -- The full photo set: p_photo_urls when the caller sent one, otherwise a
  -- single-element array from p_photo_url so a plain single-photo call (the
  -- original calling convention) still populates photo_urls consistently.
  v_photo_urls text[] := case
    when p_photo_urls is not null and array_length(p_photo_urls, 1) > 0 then p_photo_urls
    when p_photo_url is not null and btrim(p_photo_url) <> '' then array[btrim(p_photo_url)]
    else null
  end;
  v_cover text := case
    when v_photo_urls is not null and array_length(v_photo_urls, 1) > 0 then v_photo_urls[1]
    else nullif(btrim(p_photo_url), '')
  end;
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
        photo_url = coalesce(v_cover, photo_url),
        photo_urls = coalesce(v_photo_urls, photo_urls)
    where id = p_gem_id and user_id = v_owner
    returning id into v_id;
  end if;

  if v_id is null then
    insert into public.saved_gems (
      gem_name, gem_location, category, gem_coords,
      tagline, description, difficulty, best_time_to_visit,
      photo_url, photo_urls, user_id
    ) values (
      p_gem_name,
      nullif(btrim(p_gem_location), ''),
      nullif(btrim(p_category), ''),
      v_coords,
      nullif(btrim(p_tagline), ''),
      nullif(btrim(p_description), ''),
      nullif(btrim(p_difficulty), ''),
      nullif(btrim(p_best_time_to_visit), ''),
      v_cover,
      coalesce(v_photo_urls, '{}'),
      v_owner
    )
    returning id into v_id;
  end if;

  return v_id;
end;
$$;
