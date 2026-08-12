-- Unblocks reading public.trip_collaborators. RLS was enabled on this table
-- (20260630000000_create_trip_builder.sql) but no policy was ever added for
-- the table itself — every other policy only ever *references* it from a
-- subquery on trips/trip_stops/trip_bookings. With RLS-on-no-policy, Postgres
-- default-denies, so a direct `select * from trip_collaborators` returns zero
-- rows for everyone, including the trip owner. Confirmed via trip_provider.dart's
-- setPermission() TODO: "blocked by RLS until the share step adds a
-- `security definer is_trip_owner()` helper" — this migration adds exactly that.
--
-- Why security definer, not a plain policy subquery: a policy on
-- trip_collaborators that queries trip_collaborators itself (e.g. "any row
-- where another row for the same trip_id has user_id = auth.uid()") would
-- re-trigger this same policy on evaluation -> infinite recursion. Routing the
-- ownership check through a security-definer function run as the function's
-- owner (the migration role, which owns the tables) sidesteps the recursive
-- policy entirely: the function's internal query isn't re-evaluated against
-- the policy it's backing.
create or replace function public.is_trip_owner(p_trip_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.trips t
    where t.id = p_trip_id and t.owner_id = auth.uid()
  );
$$;

-- Read: the trip owner (any collaborator row on their trip) OR a collaborator
-- reading their own row. The self-row branch is a direct column compare (no
-- subquery on trip_collaborators), so it carries no recursion risk either.
-- Write policies are deliberately NOT added here — setPermission()'s
-- insert/update path is a separate "share" feature, out of scope for the Trip
-- segment's read-only Travelers card.
create policy "trip_collaborators_read" on public.trip_collaborators
  for select
  using (
    public.is_trip_owner(trip_id)
    or user_id = auth.uid()
  );

-- Confirmed / invited status, used by the Trip segment's Travelers card
-- status pill. Existing rows default to 'confirmed' (they predate any invite
-- flow, so they're already-accepted collaborators).
alter table public.trip_collaborators
  add column if not exists status text not null default 'confirmed'
    check (status in ('confirmed', 'invited'));
