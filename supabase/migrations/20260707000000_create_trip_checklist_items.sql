-- Pre-trip checklist items. One row per checklist entry, seeded from a
-- domestic/international template at trip creation
-- (TripProvider.seedChecklistForTrip). Unshipped feature work — this migration
-- has NOT been applied anywhere yet, so edits here are safe to fold in.
--
-- Idempotency: every statement is safe to re-run. Policies are wrapped in
-- pg_policies existence guards (matching the gem_saves convention). Triggers are
-- FIRST introduced to this repo in this migration, so the `drop trigger if
-- exists` guard below establishes that convention deliberately — chosen for
-- version independence (no reliance on PG14+ `create or replace trigger`), not
-- accidental style drift.

-- moddatetime is not enabled by default in Supabase; the updated_at trigger
-- below needs it. Schema-qualified so the trigger can reference it explicitly.
create extension if not exists moddatetime schema extensions;

create table if not exists public.trip_checklist_items (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  section text not null check (
    section in ('7d_before', '1d_before', 'departure_day', 'miscellaneous')
  ),
  title text not null,
  is_checked boolean not null default false,
  sort_order int not null default 0,
  due_date_offset_days int,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create index if not exists trip_checklist_items_trip_id_idx
  on public.trip_checklist_items (trip_id);

alter table public.trip_checklist_items enable row level security;

-- SELECT: owner of the parent trip can read its checklist.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'trip_checklist_items'
      and policyname = 'trip_checklist_read'
  ) then
    create policy "trip_checklist_read" on public.trip_checklist_items
      for select using (
        exists (
          select 1 from public.trips t
          where t.id = trip_checklist_items.trip_id
            and t.owner_id = auth.uid()
        )
      );
  end if;
end $$;

-- INSERT / UPDATE / DELETE: same owner join. FOR ALL with no WITH CHECK falls
-- back to the USING predicate for inserts (matches the trip_stops convention).
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'trip_checklist_items'
      and policyname = 'trip_checklist_write'
  ) then
    create policy "trip_checklist_write" on public.trip_checklist_items
      for all using (
        exists (
          select 1 from public.trips t
          where t.id = trip_checklist_items.trip_id
            and t.owner_id = auth.uid()
        )
      );
  end if;
end $$;

-- Per-section sort_order auto-assign, insert-only. The `= 0` guard means an
-- explicit sort_order (the 1-based template values) is left untouched; only
-- rows inserted without one get the next slot.
create or replace function public.set_trip_checklist_sort_order()
returns trigger as $$
begin
  if new.sort_order = 0 then
    select coalesce(max(sort_order), 0) + 1 into new.sort_order
    from public.trip_checklist_items
    where trip_id = new.trip_id and section = new.section;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trip_checklist_items_sort_order on public.trip_checklist_items;
create trigger trip_checklist_items_sort_order
  before insert on public.trip_checklist_items
  for each row execute function public.set_trip_checklist_sort_order();

-- updated_at maintenance on every UPDATE.
drop trigger if exists set_trip_checklist_updated_at on public.trip_checklist_items;
create trigger set_trip_checklist_updated_at
  before update on public.trip_checklist_items
  for each row execute function extensions.moddatetime(updated_at);
