-- Editorial content for the gem detail screen's richer, Klook-inspired
-- sections — captioned photos and "Good to Know" tips. Curated-gem-only by
-- design: nothing populates these for Mapbox-sourced POIs, and the detail
-- screen omits each section entirely when empty rather than showing a
-- placeholder (same rule as the existing best_time_to_visit field).
--
-- photo_captions is keyed by photo URL (not aligned by array index to
-- photo_urls) — a URL key self-heals if photos are ever reordered/removed;
-- an index-aligned array would silently misalign in that case.
--
-- The narrative "What to expect" section reuses the existing `description`
-- column (already unconstrained text, already rendered unclamped in the UI)
-- rather than adding a redundant field — only the section's UI label
-- changes, not the schema.
alter table public.saved_gems
  add column if not exists photo_captions jsonb not null default '{}'::jsonb,
  add column if not exists good_to_know text[] not null default '{}'::text[];
