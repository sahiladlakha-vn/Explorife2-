-- Supabase's linter flags "Users can insert own gems" (saved_gems' INSERT
-- policy) for calling auth.uid() directly in WITH CHECK: Postgres re-runs an
-- un-wrapped auth.*() call once per candidate row, where wrapping it in a
-- `select` lets the planner cache it as a per-statement init-plan instead.
-- See https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select
--
-- This assumes the policy's current check is the standard
-- `auth.uid() = user_id` this codebase uses everywhere else (e.g.
-- gem_saves' own insert policy, 20260618000100_create_gem_saves.sql) — there
-- is no tracked migration for saved_gems' own policies to confirm the exact
-- existing text against, since the table predates this repo's migration
-- history. If the live policy differs, adjust the `with check` clause below
-- to match before applying.
drop policy if exists "Users can insert own gems" on public.saved_gems;

create policy "Users can insert own gems"
  on public.saved_gems
  for insert
  with check ((select auth.uid()) = user_id);

-- The linter's usual companion recommendation: the column the policy filters
-- on should be indexed so the RLS check itself is cheap at scale.
create index if not exists saved_gems_user_id_idx on public.saved_gems (user_id);
