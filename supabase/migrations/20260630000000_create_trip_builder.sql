-- Trip Builder feature surface: one migration, four tables.
-- Conventions match existing migrations: public. prefix, if not exists, uuid ids.

create table if not exists public.trips (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  location text not null,
  start_date date not null,
  end_date date not null,
  budget_vnd bigint not null default 0,
  currency text not null default 'VND',
  vibe text,
  template_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.trip_stops (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  day int not null,
  slot text not null check (slot in ('morning','afternoon','evening')),
  gem_id uuid references public.saved_gems(id) on delete set null,
  custom_payload jsonb,
  price_vnd bigint not null default 0,
  sort_order int not null default 0
);

create table if not exists public.trip_collaborators (
  trip_id uuid not null references public.trips(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  permission text not null check (permission in ('view','edit')),
  primary key (trip_id, user_id)
);

create table if not exists public.trip_blueprints (
  id uuid primary key default gen_random_uuid(),
  location text not null,
  title text not null,
  meta text,
  items_json jsonb not null,
  save_count int default 0,
  created_at timestamptz not null default now()
);

-- Blueprints are shared, read-only templates: no RLS (public catalogue).
alter table public.trips                enable row level security;
alter table public.trip_stops           enable row level security;
alter table public.trip_collaborators   enable row level security;

-- Read: owner OR a collaborator (any permission) may see the trip.
create policy "trips_read_own_or_collab" on public.trips for select
  using (
    owner_id = auth.uid()
    or exists (
      select 1 from public.trip_collaborators c
       where c.trip_id = trips.id and c.user_id = auth.uid()
    )
  );

-- Write: only the owner. (FOR ALL also re-grants SELECT to the owner.)
create policy "trips_write_own" on public.trips for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- Stops inherit trip access. The owner branch (t.owner_id = auth.uid()) lets the
-- owner write even with NO trip_collaborators row; the collaborator branch adds
-- edit-permission members. FOR ALL with no WITH CHECK reuses USING for inserts.
create policy "trip_stops_via_trip" on public.trip_stops for all
  using (
    exists (
      select 1 from public.trips t
       where t.id = trip_stops.trip_id and (
         t.owner_id = auth.uid()
         or exists (
           select 1 from public.trip_collaborators c
            where c.trip_id = t.id and c.user_id = auth.uid() and c.permission = 'edit'
         )
       )
    )
  );
