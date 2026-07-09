-- Reconcile drift: public.hike_tracks was created outside tracked migrations and
-- shipped without the per-user column the app depends on. HikeProvider.fetchHikes
-- filters on user_id, logHike inserts it, and HikeTrack.fromJson requires it, so
-- reads currently fail in prod with 42703 (column hike_tracks.user_id does not exist).
--
-- The table is empty in prod, so the NOT NULL column adds cleanly with no backfill.
-- Conventions match existing migrations: public. prefix, if not exists, uuid, FK to
-- auth.users on delete cascade.

alter table public.hike_tracks
  add column if not exists user_id uuid not null references auth.users (id) on delete cascade;

-- Look up "all hikes for this user" cheaply (fetchHikes filters + orders by user).
create index if not exists hike_tracks_user_id_idx on public.hike_tracks (user_id);
