-- Fixes a bug from the immediately-preceding migration
-- (20260824000000_add_multi_photo_to_upsert_gem_from_sheet.sql): adding
-- p_photo_urls via CREATE OR REPLACE FUNCTION did NOT replace the original
-- 11-parameter function in place as intended — Postgres treated it as a
-- genuinely separate overload, since CREATE OR REPLACE only reuses the same
-- function object when the parameter list is unchanged (adding a parameter,
-- even with a default, doesn't qualify). With both overloads coexisting, any
-- call passing exactly the original 11 named parameters became ambiguous
-- ("Could not choose the best candidate function") — this broke EVERY sync
-- from the sheet script, not just multi-photo ones, until this is fixed.
--
-- Fix: drop the old 11-parameter overload so only the 12-parameter one (with
-- p_photo_urls defaulting to null, already handled gracefully in the
-- function body) remains — a single candidate can't be ambiguous.
drop function if exists public.upsert_gem_from_sheet(
  uuid, text, text, text, double precision, double precision, text, text, text, text, text
);

-- Explicit, rather than relying on whatever the surviving function happened
-- to inherit — self-documenting and correct regardless of prior state.
grant execute on function public.upsert_gem_from_sheet(
  uuid, text, text, text, double precision, double precision, text, text, text, text, text, text[]
) to anon;
