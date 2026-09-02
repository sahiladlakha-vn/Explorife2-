-- Sheet -> Supabase sync entry point for Tours, mirroring
-- upsert_gem_from_sheet's exact shape (security definer RPC, anon-callable,
-- server-side validation as the real enforcement point — the .gs script's
-- own checks are just a fast-fail UX nicety, same philosophy as the Gem
-- sync's heritage/landmark fix comment explains). See
-- docs/integrations/tour-sheet-sync.gs.
--
-- Unlike saved_gems, `tours` has no owner/user_id column (it's publicly
-- curated content, not a per-user saved list) — so there's no owner check
-- on update, just a plain id match.
--
-- List-type columns (photos/guide_languages/includes/highlights/itinerary)
-- use the same "only overwrite if the incoming value actually has content"
-- idempotency rule as upsert_gem_from_sheet's photo_urls handling: a
-- re-sync that temporarily resolves an empty list (e.g. a blank cell)
-- doesn't wipe out what's already there.
create or replace function public.upsert_tour_from_sheet(
  p_tour_id uuid,
  p_name text,
  p_category text,
  p_price_from integer,
  p_currency text,
  p_duration_label text,
  p_cancellation_policy text,
  p_pickup_included boolean,
  p_pickup_detail text,
  p_guide_languages text[],
  p_includes text[],
  p_itinerary jsonb,
  p_highlights text[],
  p_full_description text,
  p_is_curated boolean,
  p_photos text[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_photos text[] := case
    when p_photos is not null and array_length(p_photos, 1) > 0 then p_photos
    else null
  end;
  v_guide_languages text[] := case
    when p_guide_languages is not null and array_length(p_guide_languages, 1) > 0 then p_guide_languages
    else null
  end;
  v_includes text[] := case
    when p_includes is not null and array_length(p_includes, 1) > 0 then p_includes
    else null
  end;
  v_highlights text[] := case
    when p_highlights is not null and array_length(p_highlights, 1) > 0 then p_highlights
    else null
  end;
  v_itinerary jsonb := case
    when p_itinerary is not null and jsonb_array_length(p_itinerary) > 0 then p_itinerary
    else null
  end;
begin
  if p_name is null or btrim(p_name) = '' then
    raise exception 'name is required';
  end if;

  -- Same 10-category taxonomy as Gem.categories / VALID_CATEGORIES in both
  -- gem-sheet-sync.gs and tour-sheet-sync.gs, and same "optional but
  -- validated if present" rule as upsert_gem_from_sheet's own category
  -- check — Tour.category is nullable (lib/models/tour.dart), so an
  -- uncategorized tour is allowed, but a WRONG category value is not.
  if p_category is not null and btrim(p_category) <> '' and p_category not in (
    'hiking', 'camping', 'viewpoint', 'food', 'temple', 'cave', 'coastal',
    'nature', 'heritage', 'landmark'
  ) then
    raise exception 'invalid category: %', p_category;
  end if;

  if p_price_from is not null and p_price_from < 0 then
    raise exception 'price_from must be non-negative';
  end if;

  -- Same VALID_CURRENCIES list as tour-sheet-sync.gs — extend both together.
  if p_currency is not null and btrim(p_currency) <> '' and p_currency not in ('VND', 'USD') then
    raise exception 'invalid currency: %', p_currency;
  end if;

  if p_tour_id is not null then
    update public.tours
    set name = p_name,
        category = nullif(btrim(p_category), ''),
        price_from = coalesce(p_price_from, price_from),
        currency = coalesce(nullif(btrim(p_currency), ''), currency),
        duration_label = nullif(btrim(p_duration_label), ''),
        cancellation_policy = nullif(btrim(p_cancellation_policy), ''),
        pickup_included = coalesce(p_pickup_included, pickup_included),
        pickup_detail = nullif(btrim(p_pickup_detail), ''),
        guide_languages = coalesce(v_guide_languages, guide_languages),
        includes = coalesce(v_includes, includes),
        itinerary = coalesce(v_itinerary, itinerary),
        highlights = coalesce(v_highlights, highlights),
        full_description = nullif(btrim(p_full_description), ''),
        is_curated = coalesce(p_is_curated, is_curated),
        photos = coalesce(v_photos, photos)
    where id = p_tour_id
    returning id into v_id;
  end if;

  if v_id is null then
    insert into public.tours (
      name, category, price_from, currency, duration_label,
      cancellation_policy, pickup_included, pickup_detail,
      guide_languages, includes, itinerary, highlights,
      full_description, is_curated, photos
    ) values (
      p_name,
      nullif(btrim(p_category), ''),
      coalesce(p_price_from, 0),
      coalesce(nullif(btrim(p_currency), ''), 'VND'),
      nullif(btrim(p_duration_label), ''),
      nullif(btrim(p_cancellation_policy), ''),
      coalesce(p_pickup_included, false),
      nullif(btrim(p_pickup_detail), ''),
      coalesce(v_guide_languages, '{}'),
      coalesce(v_includes, '{}'),
      coalesce(v_itinerary, '[]'),
      coalesce(v_highlights, '{}'),
      nullif(btrim(p_full_description), ''),
      coalesce(p_is_curated, false),
      coalesce(v_photos, '{}')
    )
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

-- Anon-callable, same as upsert_gem_from_sheet — the sheet script has no
-- user session, only the anon key (see tour-sheet-sync.gs's setup()).
grant execute on function public.upsert_tour_from_sheet(
  uuid, text, text, integer, text, text, text, boolean, text,
  text[], text[], jsonb, text[], text, boolean, text[]
) to anon;
