-- Per-category planned budget for a trip. One row per spend bucket, seeded from
-- a vibe-based proportional split at trip creation
-- (TripProvider.seedCategoryBudgetsForTrip). This is the "planned" source for
-- the Summary Planned-vs-Actual chart; the actual editing UI is deferred, so
-- today these rows are only ever written by the seed. Unshipped feature work —
-- this migration has NOT been applied anywhere yet, so edits here are safe.
--
-- Idempotency: every statement is safe to re-run. Policies are wrapped in
-- pg_policies existence guards (matching the gem_saves convention); the trigger
-- uses `drop trigger if exists` before create (the version-independent trigger
-- convention established in the trip_checklist_items migration).

-- moddatetime is not enabled by default in Supabase; the updated_at trigger
-- below needs it. Schema-qualified so the trigger can reference it explicitly.
-- (create extension is idempotent — a no-op if the checklist migration already
-- enabled it.)
create extension if not exists moddatetime schema extensions;

-- The category CHECK lists eight buckets for forward room, but the seed and the
-- Summary chart only use four (stay/food/activity/transit) — mirrors
-- TripProvider.categoryTotals. The extra values are reserved, not yet written.
create table if not exists public.trip_category_budgets (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  category text not null check (
    category in (
      'stay', 'food', 'activity', 'transit',
      'shopping', 'insurance', 'misc', 'flights'
    )
  ),
  planned_vnd bigint not null default 0,
  updated_at timestamptz,
  unique(trip_id, category)
);

create index if not exists trip_category_budgets_trip_id_idx
  on public.trip_category_budgets (trip_id);

alter table public.trip_category_budgets enable row level security;

-- SELECT: owner of the parent trip can read its budgets.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'trip_category_budgets'
      and policyname = 'trip_category_budgets_read'
  ) then
    create policy "trip_category_budgets_read" on public.trip_category_budgets
      for select using (
        exists (
          select 1 from public.trips t
          where t.id = trip_category_budgets.trip_id
            and t.owner_id = auth.uid()
        )
      );
  end if;
end $$;

-- INSERT / UPDATE / DELETE: same owner join. FOR ALL with no WITH CHECK falls
-- back to the USING predicate for inserts (matches the trip_checklist_items
-- and trip_stops convention).
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'trip_category_budgets'
      and policyname = 'trip_category_budgets_write'
  ) then
    create policy "trip_category_budgets_write" on public.trip_category_budgets
      for all using (
        exists (
          select 1 from public.trips t
          where t.id = trip_category_budgets.trip_id
            and t.owner_id = auth.uid()
        )
      );
  end if;
end $$;

-- updated_at maintenance on every UPDATE.
drop trigger if exists set_trip_category_budgets_updated_at on public.trip_category_budgets;
create trigger set_trip_category_budgets_updated_at
  before update on public.trip_category_budgets
  for each row execute function extensions.moddatetime(updated_at);
