-- Estimated visit duration, for the Itinerary spot row's meta line
-- (category · duration · cost) and the day-summary planned-time rollup.
-- Confirmed via information_schema.columns that saved_gems has no existing
-- duration/est_time column before adding this (13 columns checked: id,
-- user_id, gem_coords, saved_at, category, gem_type, tagline,
-- best_time_to_visit, difficulty, description, photo_url, gem_name,
-- gem_location — none of them a duration).
--
-- Nullable, no default: an unset duration means "unknown", not "zero
-- minutes" — the rollup helper must treat it as excluded from the sum, not
-- as a zero contribution.
alter table public.saved_gems
  add column if not exists est_duration_min int;
