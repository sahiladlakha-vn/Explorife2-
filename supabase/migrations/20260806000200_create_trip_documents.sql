-- Trip documents: passports/visas/tickets/reservations/insurance attached to
-- a trip, optionally scoped to one traveler. Backs the Trip segment's
-- Documents card. Conventions match existing trip migrations: public.
-- prefix, if not exists, uuid ids, RLS copied verbatim from trip_stops_via_trip.

create table if not exists public.trip_documents (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  -- null = shared (belongs to the whole trip, e.g. a group reservation).
  -- SET NULL (not CASCADE): removing a traveler must not delete the document,
  -- just fall it back to "shared".
  owner_collaborator_id uuid references public.trip_collaborators(id) on delete set null,
  type text not null
    check (type in ('passport', 'visa', 'ticket', 'reservation', 'insurance')),
  title text not null,
  file_url text,
  expires_on date,
  created_at timestamptz not null default now()
);

create index if not exists trip_documents_trip_id_idx
  on public.trip_documents (trip_id);

alter table public.trip_documents enable row level security;

-- Copied verbatim from trip_stops_via_trip (20260630000000_create_trip_builder.sql):
-- owner branch lets the owner write with no trip_collaborators row at all;
-- collaborator branch adds edit-permission members. FOR ALL with no WITH CHECK
-- reuses USING for inserts.
create policy "trip_documents_via_trip" on public.trip_documents for all
  using (
    exists (
      select 1 from public.trips t
       where t.id = trip_documents.trip_id and (
         t.owner_id = auth.uid()
         or exists (
           select 1 from public.trip_collaborators c
            where c.trip_id = t.id and c.user_id = auth.uid() and c.permission = 'edit'
         )
       )
    )
  );
