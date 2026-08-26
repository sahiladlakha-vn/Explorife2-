-- Real gem data upload — sourced from the user's spreadsheet
-- (https://docs.google.com/spreadsheets/d/1NMbA92zRJ134zaGCmzSJNT2Pyh7UlYP0lRtNhhbXIFk).
-- Coordinates are geocoded from the text address (OpenStreetMap Nominatim) at
-- street-level precision — Nominatim couldn't resolve the exact house number,
-- so this pin lands on the street, not the specific building. Good enough for
-- map plotting; adjustable later via the app's own edit flow if one exists.
--
-- gem_coords matches Gem.toInsert()'s wire shape exactly: a {"lat", "lng"}
-- JSON object (not a [lng, lat] array — Gem.fromJson accepts both, but this
-- app's own writer only ever produces the map form, so new rows should match
-- it for consistency with everything the app itself inserts).
--
-- photo_url / tagline / description / difficulty / best_time_to_visit /
-- est_duration_min are all left null per the user's choice — the app's
-- ImageFallback tile covers the no-photo case gracefully already.
insert into public.saved_gems (
  user_id,
  gem_name,
  gem_location,
  category,
  gem_coords
) values (
  '0f513f84-c0d2-4718-94f0-1f9fbfa1f3ef',
  'Bánh căn Cô Hiếu',
  '49 Đường số 24, Long Bình, Hồ Chí Minh, Vietnam',
  'food',
  jsonb_build_object('lat', 10.8457461, 'lng', 106.8282119)
);
