-- Trip packing list: itemized, optionally assigned to a traveler, with a
-- packed/unpacked toggle. Backs the Trip segment's Packing card. Conventions
-- match existing trip migrations: public. prefix, if not exists, uuid ids,
-- RLS copied verbatim from trip_stops_via_trip.
--
-- Dedicated table rather than extending trip_checklist_items with a `kind`
-- column (flagged in the prompt as a decision point): packing needs
-- assignee + quantity + category, none of which trip_checklist_items has or
-- needs for its own pre-trip-task purpose. Bolting those onto the generic
-- checklist would bloat every checklist row with packing-only nullable
-- columns; a dedicated table keeps both concerns narrow.

create table if not exists public.trip_packing_items (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  -- null = unassigned / shared item (e.g. "first aid kit" for the group).
  -- SET NULL: removing a traveler must not delete the item, just unassign it.
  assignee_collaborator_id uuid references public.trip_collaborators(id) on delete set null,
  label text not null,
  category text,
  quantity int not null default 1,
  is_packed boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists trip_packing_items_trip_id_idx
  on public.trip_packing_items (trip_id);

alter table public.trip_packing_items enable row level security;

-- Copied verbatim from trip_stops_via_trip (20260630000000_create_trip_builder.sql).
create policy "trip_packing_items_via_trip" on public.trip_packing_items for all
  using (
    exists (
      select 1 from public.trips t
       where t.id = trip_packing_items.trip_id and (
         t.owner_id = auth.uid()
         or exists (
           select 1 from public.trip_collaborators c
            where c.trip_id = t.id and c.user_id = auth.uid() and c.permission = 'edit'
         )
       )
    )
  );
