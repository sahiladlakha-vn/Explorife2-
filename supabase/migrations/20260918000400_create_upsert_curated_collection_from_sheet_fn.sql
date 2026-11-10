-- Sheet -> Supabase sync entry point for curated collections, mirroring
-- upsert_tour_from_sheet's exact shape (security definer RPC, anon-
-- callable, server-side validation as the real enforcement point). See
-- docs/integrations/collection-sheet-sync.gs.
--
-- No owner/user_id column (same as tours) — publicly curated content, not
-- a per-user list, so update is a plain id match.
create or replace function public.upsert_curated_collection_from_sheet(
  p_collection_id uuid,
  p_title text,
  p_subtitle text,
  p_cover_image_url text,
  p_is_destination boolean,
  p_scope_value text,
  p_rating numeric,
  p_best_time_to_visit text,
  p_sort_order integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_title is null or btrim(p_title) = '' then
    raise exception 'title is required';
  end if;

  if p_scope_value is null or btrim(p_scope_value) = '' then
    raise exception 'scope value is required';
  end if;

  -- Same 10-category taxonomy as Gem.categories / VALID_CATEGORIES in
  -- gem-sheet-sync.gs, tour-sheet-sync.gs, and collection-sheet-sync.gs —
  -- only enforced for category-scoped rows (is_destination = false); a
  -- destination row's scope_value is a free-text city name, not validated
  -- against a fixed list (same as the Dart model never validating it
  -- either — resolved live via GeocodingService on tap).
  if p_is_destination = false and btrim(p_scope_value) <> 'all' and btrim(p_scope_value) not in (
    'hiking', 'camping', 'viewpoint', 'food', 'temple', 'cave', 'coastal',
    'nature', 'heritage', 'landmark'
  ) then
    raise exception 'invalid category scope value: %', p_scope_value;
  end if;

  if p_rating is not null and (p_rating < 0 or p_rating > 5) then
    raise exception 'rating must be between 0 and 5';
  end if;

  if p_collection_id is not null then
    update public.curated_collections
    set title = p_title,
        subtitle = nullif(btrim(p_subtitle), ''),
        cover_image_url = nullif(btrim(p_cover_image_url), ''),
        is_destination = coalesce(p_is_destination, is_destination),
        scope_value = btrim(p_scope_value),
        rating = p_rating,
        best_time_to_visit = nullif(btrim(p_best_time_to_visit), ''),
        sort_order = coalesce(p_sort_order, sort_order),
        source = 'sheet_sync'
    where id = p_collection_id
    returning id into v_id;
  end if;

  if v_id is null then
    insert into public.curated_collections (
      title, subtitle, cover_image_url, is_destination, scope_value,
      rating, best_time_to_visit, sort_order, source
    ) values (
      p_title,
      nullif(btrim(p_subtitle), ''),
      nullif(btrim(p_cover_image_url), ''),
      coalesce(p_is_destination, true),
      btrim(p_scope_value),
      p_rating,
      nullif(btrim(p_best_time_to_visit), ''),
      coalesce(p_sort_order, 0),
      'sheet_sync'
    )
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

grant execute on function public.upsert_curated_collection_from_sheet(
  uuid, text, text, text, boolean, text, numeric, text, integer
) to anon;
