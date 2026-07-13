-- Trip bookings: flights, stays, activities and transport reserved against a
-- trip (optionally pinned to a specific stop). One migration, one table + RLS.
-- Conventions match existing migrations: public. prefix, if not exists, uuid ids,
-- money as *_vnd bigint (house pattern: budget_vnd, price_vnd, planned_vnd).

create table if not exists public.trip_bookings (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  -- Optional link to the itinerary stop this booking covers. SET NULL (not
  -- CASCADE): deleting a stop must not silently delete a paid reservation.
  stop_id uuid references public.trip_stops(id) on delete set null,
  booking_type text not null
    check (booking_type in ('flight','stay','activity','transport')),
  title text not null,
  confirmation_ref text,
  provider text,
  start_at timestamptz,
  end_at timestamptz,
  -- Nullable on purpose: a 'to_book' item has no known price yet, and 0 (a free
  -- reservation) must stay distinguishable from "unknown". Same _vnd bigint type
  -- as the rest of the trip world so budget/pace math never mixes currencies.
  amount_vnd bigint,
  status text not null default 'to_book'
    check (status in ('to_book','booked','paid')),
  -- Informational author. Matches trips.owner_id by referencing auth.users(id)
  -- rather than public.profiles (profiles is not versioned in this repo, and the
  -- house FK target for ownership columns is auth.users). SET NULL so a deleted
  -- account doesn't cascade-delete the trip's bookings.
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- FK-backed access paths for the common reads (all bookings for a trip; the
-- booking pinned to a stop). The trip_builder migration added none, but these
-- two queries run on every profile "My Trip" load, so index them explicitly.
create index if not exists trip_bookings_trip_id_idx
  on public.trip_bookings (trip_id);
create index if not exists trip_bookings_stop_id_idx
  on public.trip_bookings (stop_id);

alter table public.trip_bookings enable row level security;

-- Bookings inherit trip access, copied VERBATIM from trip_stops_via_trip: the
-- owner branch (t.owner_id = auth.uid()) lets the owner write even with NO
-- trip_collaborators row; the collaborator branch adds edit-permission members.
-- FOR ALL with no WITH CHECK reuses USING for inserts. This policy lives on
-- trip_bookings and only READS trips + trip_collaborators in subqueries — it
-- puts no policy on trip_collaborators, so it stays clear of the collaborator
-- RLS recursion trap.
create policy "trip_bookings_via_trip" on public.trip_bookings for all
  using (
    exists (
      select 1 from public.trips t
       where t.id = trip_bookings.trip_id and (
         t.owner_id = auth.uid()
         or exists (
           select 1 from public.trip_collaborators c
            where c.trip_id = t.id and c.user_id = auth.uid() and c.permission = 'edit'
         )
       )
    )
  );
