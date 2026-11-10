-- Migrates the 4 entries that were hardcoded in
-- lib/core/constants/curated_collections.dart (CuratedCollections.all) into
-- the new table, verbatim — this is what keeps Home's "EXPLORE IDEAS" rail
-- showing the exact same content once the app switches to reading from
-- Supabase instead of the static list; without this the rail would go
-- empty on that switch. Same "draft content, not yet content-owner-
-- confirmed" caveat the Dart file's own doc comment carried.
insert into public.curated_collections (
  title, subtitle, cover_image_url, is_destination, scope_value,
  rating, best_time_to_visit, sort_order
) values
(
  'Explore Hanoi',
  'Vietnam''s capital — Old Quarter, lakes & street food',
  'https://images.unsplash.com/photo-1547024842-a0e3d2127406?w=800&q=80',
  true, 'Hanoi', 4.7, 'Oct–Dec', 0
),
(
  'Explore Ho Chi Minh City',
  'Markets, rooftop cafés & war history',
  'https://images.unsplash.com/photo-1583417319070-4a69db38a482?w=800&q=80',
  true, 'Ho Chi Minh City', 4.6, 'Dec–Apr', 1
),
(
  'Trending: Hiking Trails',
  'Real trails, tagged by real hikers',
  'https://images.unsplash.com/photo-1551632811-561732d1e306?w=800&q=80',
  false, 'hiking', null, null, 2
),
(
  'Hidden Food & Cafés',
  'Spots you won''t find on a map app',
  'https://images.unsplash.com/photo-1554118811-1e0d58224f24?w=800&q=80',
  false, 'food', null, null, 3
);
