-- Verification-only: seeds photo_captions/good_to_know onto the existing
-- "Multi-photo test gem" test row (already has 2 photo_urls from earlier
-- multi-photo testing) so the new GemDetailScreen sections can be checked
-- against real data — there's no gem-editing UI yet to do this through the
-- app itself (confirmed: creation-only scope for these new fields).
update public.saved_gems
set
  photo_captions = jsonb_build_object(
    'https://images.unsplash.com/photo-1.jpg', 'A quiet corner that captures why people love this spot.',
    'https://images.unsplash.com/photo-2.jpg', 'The view everyone comes back for.'
  ),
  description = 'Tucked away from the main road, this place has a way of slowing you down the moment you arrive. Mornings are quiet and golden-lit; by afternoon the tables fill with regulars who treat it like a second living room. Come hungry, stay for the conversation.',
  good_to_know = array[
    'Best visited early morning or late afternoon to avoid the midday heat',
    'Cash only — no cards accepted',
    'Bring a light jacket if visiting in the evening'
  ]
where id = 'd35480ee-ca1f-49d5-818d-384d4a5afb01';
