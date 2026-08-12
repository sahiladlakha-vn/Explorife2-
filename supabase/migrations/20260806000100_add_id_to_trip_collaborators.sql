-- Gives trip_collaborators a single-column identity so trip_documents /
-- trip_packing_items can FK to "this specific collaborator" rather than
-- carrying a (trip_id, user_id) pair each. Added as a `unique` sidecar, NOT a
-- new primary key: trip_provider.dart's setPermission() does
-- `.upsert({trip_id, user_id, permission})` with no `onConflict` argument,
-- which resolves against the table's PRIMARY KEY. Swapping the PK to `id`
-- would silently turn that upsert into an always-insert (every call would
-- conflict on a fresh random id instead of the intended (trip_id, user_id)
-- pair). The existing composite PK stays exactly as-is.
alter table public.trip_collaborators
  add column if not exists id uuid unique not null default gen_random_uuid();
