-- MIGRATION_PLAN.md §6 Risk #1 / §7 Step 3 "still open" item 1.
--
-- `hike_tracks` is live with only (id, name, route, featured, created_at,
-- user_id), but `HikeProvider.logHike()`/`fetchHikes()`
-- (lib/providers/hike_provider.dart) and `HikeTrack.fromJson()`
-- (lib/models/hike.dart) read/write six columns that don't exist on the live
-- table: title, activity_type, distance_km, duration_seconds,
-- elevation_gain_m, started_at. Every `logHike()` insert currently fails
-- with Postgres error 42703 (undefined_column) — the activity-logging
-- feature is fully broken in production today.
--
-- Decision (approved, §6 Risk #1): extend the table additively to match the
-- Dart model's intent. No existing column is renamed, dropped, or retyped.
-- `prisma/schema.prisma`'s `HikeTrack` model already declares these six
-- fields (hand-built ahead of this migration, per Step 3) — this file is
-- the SQL to bring the live table in sync with that model. Generated via:
--
--   npx prisma migrate diff \
--     --from-schema-datamodel <HikeTrack reverted to its live 6-column shape> \
--     --to-schema-datamodel prisma/schema.prisma --script
--
-- (schema-to-schema diffing — no live DB connection used or required to
-- produce this file; nothing has been applied yet, see note below).
--
-- `title`/`activity_type`/`started_at` are declared NOT NULL with a default
-- (matching the Dart model's `required` fields and its own fallback
-- defaults in `HikeTrack.fromJson` — 'Untitled Hike' / 'hiking' / now()) so
-- the ADD COLUMN is safe even though the table is non-empty in general;
-- today it has 0 live rows (see MIGRATION_PLAN.md §3), so no backfill is
-- needed either way. `distance_km`/`duration_seconds`/`elevation_gain_m`
-- stay nullable, matching both the Dart model (`double?`/`int?`/`double?`)
-- and `logHike()`'s optional parameters.
--
-- NOT applied to the live database by this commit — per MIGRATION_PLAN.md's
-- "Migration safety rules", schema changes only ever go live via
-- `prisma migrate deploy` after human review, and this migration is further
-- sequenced after the Step 3 baseline (`0_init`, marking the already-live
-- schema as applied via `prisma migrate resolve --applied`), which is the
-- user's own local step, not performed by the agent.

-- AlterTable
ALTER TABLE "hike_tracks" ADD COLUMN     "activity_type" TEXT NOT NULL DEFAULT 'hiking',
ADD COLUMN     "distance_km" DOUBLE PRECISION,
ADD COLUMN     "duration_seconds" INTEGER,
ADD COLUMN     "elevation_gain_m" DOUBLE PRECISION,
ADD COLUMN     "started_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "title" TEXT NOT NULL DEFAULT 'Untitled Hike';
