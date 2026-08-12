-- Companion to 20260806000000's read policy and 20260806000400's backfill:
-- without this, TripProvider.createTrip()'s new owner-collaborator-row
-- insert (and the backfill migration, if it were ever re-run as a
-- non-superuser) would fail under RLS — the earlier migration only ever
-- added a SELECT policy on trip_collaborators, nothing for INSERT, so
-- Postgres' default-deny still blocked every write.
--
-- Scoped to the trip owner only (via the same non-recursive is_trip_owner()
-- helper): this covers today's need (the owner inserting their own row) and
-- is also the right shape for a future real "invite a collaborator" flow —
-- an owner should be the one who can add rows to their own trip's
-- collaborator list, not an arbitrary authenticated user.
create policy "trip_collaborators_insert_by_owner" on public.trip_collaborators
  for insert
  with check ( public.is_trip_owner(trip_id) );
