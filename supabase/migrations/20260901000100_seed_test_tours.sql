-- Verification-only seed — 2 example tours so ToursListScreen/TourDetailScreen
-- can be checked against real-shaped data (there's no creation UI yet to add
-- these through the app itself). Real photos, real Hanoi/Ha Long content, not
-- lorem — but titles/copy/pricing are drafts and should be confirmed by
-- whoever owns this content before being treated as production-ready, same
-- caveat curated_collections.dart's own seed content carries.
insert into public.tours (
  name, photos, category, price_from, currency, duration_label,
  cancellation_policy, pickup_included, pickup_detail, guide_languages,
  includes, itinerary, highlights, full_description, is_curated
) values (
  'Ha Long Bay Day Cruise',
  array[
    'https://images.unsplash.com/photo-1528127269322-539801943592?w=800&q=80',
    'https://images.unsplash.com/photo-1528127269322-539801943592?w=800&q=80'
  ],
  'coastal',
  1200000,
  'VND',
  'Full day (10 hours)',
  'Free cancellation up to 24 hours before departure',
  true,
  'Hotel pickup included within Hanoi Old Quarter',
  array['English', 'Vietnamese'],
  array['Cruise ticket', 'Lunch on board', 'Kayaking', 'Hotel pickup and drop-off'],
  '[
    {"title": "Hotel pickup", "description": "Pickup from your Hanoi hotel, 3-hour transfer to Ha Long Bay."},
    {"title": "Board the cruise", "description": "Check in, welcome drink, safety briefing."},
    {"title": "Sung Sot Cave", "description": "Guided walk through the Surprise Cave."},
    {"title": "Kayaking", "description": "Free kayaking around the limestone karsts."},
    {"title": "Lunch on board", "description": "Vietnamese seafood lunch as the boat cruises the bay."},
    {"title": "Return to Hanoi", "description": "Afternoon drive back, drop-off at your hotel."}
  ]'::jsonb,
  array['UNESCO World Heritage limestone karsts', 'Kayaking included', 'Small-group cruise'],
  'Cruise through Ha Long Bay''s limestone karsts on a full-day trip from Hanoi. Includes a guided cave walk, kayaking around the karsts, and a seafood lunch on board. Round-trip hotel transfer included.',
  true
),
(
  'Hanoi Street Food Walking Tour',
  array['https://images.unsplash.com/photo-1555126634-323283e090fa?w=800&q=80'],
  'food',
  350000,
  'VND',
  '3 hours (evening)',
  'Free cancellation up to 12 hours before start time',
  false,
  null,
  array['English'],
  array['Local guide', '6 food tastings', 'Bottled water'],
  '[
    {"title": "Old Quarter meeting point", "description": "Meet your guide at Hoan Kiem Lake."},
    {"title": "Bun cha stop", "description": "Grilled pork with noodles, a Hanoi classic."},
    {"title": "Egg coffee", "description": "Try Hanoi''s signature ca phe trung."},
    {"title": "Banh mi stop", "description": "Vietnamese baguette sandwich from a family-run stall."},
    {"title": "Dessert stop", "description": "Che (sweet soup) to finish the walk."}
  ]'::jsonb,
  array['6 tastings included', 'Small groups only', 'Local, family-run stalls'],
  'A 3-hour evening walking tour through Hanoi''s Old Quarter, stopping at 6 family-run food stalls for a real taste of local street food — bun cha, egg coffee, banh mi, and more. Ends with a sweet dessert stop.',
  false
);
