-- Baseline migration — MIGRATION_PLAN.md §7 Step 3 "still open" item 2.
--
-- Marks the already-existing live Supabase Postgres schema (hand-built into
-- `prisma/schema.prisma` via live-DB SQL introspection, see §3/§7) as
-- Prisma's starting point, so `prisma migrate dev`/`deploy` never try to
-- recreate tables that already exist on the live database.
--
-- To be applied locally, by the user, never by an agent, per
-- MIGRATION_PLAN.md's "Migration safety rules": a schema-to-schema
-- `prisma migrate diff --from-schema-datamodel prisma/schema.prisma
-- --to-schema-datamodel prisma/schema.prisma --script` against the live DB
-- must come back empty before `prisma migrate resolve --applied 0_init`
-- marks this migration applied without actually running it (the schema it
-- describes already exists). No write to `_prisma_migrations` is to be made
-- by an agent, directly or via the Supabase MCP, at any point.
--
-- REGENERATED 2026-10-29 (superseding the version committed alongside
-- `1_hike_tracks_fields`, before either migration was ever applied):
--
--   1. `gem_guides.location`'s STORED GENERATED default didn't match the
--      live expression's exact parenthesization. Live `prisma db pull
--      --print` (run by the user, who has DB credentials — the agent does
--      not) showed `(st_setsrid(st_makepoint(longitude, latitude),
--      4326))::geography`, i.e. the `st_setsrid(...)` call wrapped in its
--      own parens before the `::geography` cast — `schema.prisma` and
--      `prisma/db-notes.sql` previously had it unwrapped. Fixed in both
--      files; this regenerated baseline reflects the corrected expression.
--   2. The user's own live diff additionally found that `hike_tracks`
--      already has all twelve columns live (the original six plus `title`/
--      `activity_type`/`distance_km`/`duration_seconds`/`elevation_gain_m`/
--      `started_at`) — someone applied the Risk #1 fix (MIGRATION_PLAN.md
--      §6 item 1) directly against the live database, outside Prisma,
--      before this baseline was ever resolved as applied. Since neither
--      `0_init` nor `1_hike_tracks_fields` had been applied yet (confirmed
--      via `prisma migrate status` showing both pending), there was no
--      "already-applied migration" to preserve: `1_hike_tracks_fields` was
--      deleted outright and `hike_tracks` is created here with all twelve
--      columns in one `CREATE TABLE`, matching the live table and
--      `schema.prisma`'s `HikeTrack` model directly, instead of needing a
--      second migration to layer the extra six on afterward.
--
-- Generated via `npx prisma migrate diff --from-empty --to-schema-datamodel
-- prisma/schema.prisma --script` (schema-to-empty diffing — no live DB
-- connection used or possible here, since the agent deliberately has no DB
-- credentials). Every table here reflects `schema.prisma` exactly as it
-- stands today, confirmed against the two checks the user asked for: no
-- statement here creates, alters, or drops anything in the `auth` schema
-- (only `REFERENCES "auth"."users"(...)` foreign keys, which read an
-- existing external table, never modify it — `auth.*` is in
-- `prisma.config.ts`'s `externalTables`), and the file contains no `DROP`
-- statement at all — purely additive `CREATE SCHEMA`/`CREATE TYPE`/
-- `CREATE TABLE`/`CREATE INDEX`/`ALTER TABLE ... ADD CONSTRAINT`.
--
-- IMPORTANT — this baseline is bookkeeping only, not a full schema capture:
-- it only contains what Prisma's migration engine can express from
-- `schema.prisma` (tables, columns, defaults it understands, plain indexes,
-- foreign keys). It does NOT include check constraints, Row Level Security
-- policies, triggers, stored functions/procedures, or the GiST/GIN
-- expression indexes' underlying operator classes beyond what `@@index`
-- can declare — all of that lives only on the real Supabase project and is
-- documented separately (`prisma/db-notes.sql`, MIGRATION_PLAN.md §3a/§6).
-- A fresh local/dev database must therefore be provisioned from the
-- Supabase CLI (`supabase db pull`/a real schema dump) and NOT from
-- `prisma migrate deploy` against this migrations folder alone — replaying
-- just `0_init` gives you the tables and columns but none of the RLS/
-- trigger/function behavior the live app actually depends on.
--
-- All 30 in-scope tables plus the Risk #2 dead/legacy ones that are still
-- physically live but `@@ignore`d from the generated Prisma Client
-- (`trip_groups`, `trip_expenses`, `trip_members`, `trip_settlements`,
-- `user_saved_gems`) — included here because they already exist on the live
-- database and must be part of the baseline for `migrate diff`/`status` to
-- see no drift, even though the application never reads/writes them.
-- `auth.users` and the rest of Supabase's `auth` schema are intentionally
-- absent — `prisma.config.ts` marks every `auth.*` table/enum as
-- `externalTables`/`externalEnums`, so Prisma never generates DDL for them.

-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "user_role" AS ENUM ('traveler', 'guide', 'business_owner', 'content_moderator', 'regional_admin', 'super_admin', 'finance_admin');

-- CreateEnum
CREATE TYPE "guide_specialty" AS ENUM ('hidden_gems', 'food_tour', 'city_walk', 'coffee_chat', 'night_life', 'street_art', 'nature', 'photography');

-- CreateTable
CREATE TABLE "profiles" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL DEFAULT '',
    "avatar_url" TEXT,
    "bio" TEXT NOT NULL DEFAULT '',
    "city" TEXT NOT NULL DEFAULT '',
    "country" TEXT NOT NULL DEFAULT '',
    "languages" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "display_name" TEXT,
    "privacy_show_gps" BOOLEAN NOT NULL DEFAULT false,
    "privacy_blur_maps" BOOLEAN NOT NULL DEFAULT true,
    "username" TEXT,
    "role" "user_role" NOT NULL DEFAULT 'traveler',

    CONSTRAINT "profiles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "traveller_profiles" (
    "user_id" UUID NOT NULL,
    "date_of_birth" DATE,
    "gender" TEXT,
    "nationality" TEXT,
    "phone" TEXT,
    "login_method" TEXT,
    "preferred_language" TEXT,
    "account_status" TEXT NOT NULL DEFAULT 'active',
    "interests" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "travel_style" TEXT,
    "budget_range" TEXT,
    "home_location" TEXT,
    "verification_status" TEXT NOT NULL DEFAULT 'unverified',
    "emergency_contact" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "traveller_profiles_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "admin_profiles" (
    "user_id" UUID NOT NULL,
    "role_title" TEXT NOT NULL,
    "managed_profile_types" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "assigned_region" TEXT,
    "account_status" TEXT NOT NULL DEFAULT 'active',
    "two_factor_enabled" BOOLEAN NOT NULL DEFAULT false,
    "last_login" TIMESTAMPTZ(6),
    "last_login_ip" TEXT,
    "notes" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "admin_profiles_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "admin_action_log" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "actor_id" UUID,
    "action_type" TEXT NOT NULL,
    "target_profile_id" UUID,
    "details" JSONB,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "old_role" "user_role",
    "new_role" "user_role",

    CONSTRAINT "admin_action_log_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "leaderboard" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID,
    "display_name" TEXT,
    "avatar_url" TEXT,
    "gems_discovered" INTEGER DEFAULT 0,
    "journals_written" INTEGER DEFAULT 0,
    "countries_visited" INTEGER DEFAULT 0,
    "total_saves" INTEGER DEFAULT 0,
    "rank_score" INTEGER DEFAULT ((((gems_discovered * 3) + (journals_written * 5)) + (countries_visited * 10)) + total_saves),
    "updated_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "leaderboard_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "saved_gems" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID,
    "gem_name" TEXT NOT NULL,
    "gem_location" TEXT,
    "category" TEXT,
    "gem_coords" JSONB,
    "saved_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "best_time_to_visit" TEXT,
    "difficulty" TEXT,
    "description" TEXT,
    "photo_url" TEXT,
    "gem_type" TEXT DEFAULT 'gem',
    "tagline" TEXT,
    "est_duration_min" INTEGER,
    "photo_urls" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "photo_captions" JSONB NOT NULL DEFAULT '{}',
    "good_to_know" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "source" TEXT NOT NULL DEFAULT 'app',

    CONSTRAINT "saved_gems_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "gem_guides" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "user_id" UUID NOT NULL,
    "specialties" "guide_specialty"[] DEFAULT ARRAY[]::"guide_specialty"[],
    "rating" DECIMAL(3,2) NOT NULL DEFAULT 0.00,
    "total_hosted" INTEGER NOT NULL DEFAULT 0,
    "verified" BOOLEAN NOT NULL DEFAULT false,
    "latitude" DOUBLE PRECISION NOT NULL,
    "longitude" DOUBLE PRECISION NOT NULL,
    "location" geography(Point, 4326) DEFAULT (st_setsrid(st_makepoint(longitude, latitude), 4326))::geography,
    "available" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "gem_guides_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "hosting_offers" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "guide_id" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "type" "guide_specialty" NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "capacity" INTEGER NOT NULL DEFAULT 2,
    "duration_hours" DECIMAL(4,1) NOT NULL DEFAULT 2.0,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "hosting_offers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "gem_saves" (
    "user_id" UUID NOT NULL,
    "gem_id" UUID NOT NULL,
    "saved_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "gem_saves_pkey" PRIMARY KEY ("user_id","gem_id")
);

-- CreateTable
CREATE TABLE "hike_tracks" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name" TEXT,
    "route" JSONB,
    "featured" BOOLEAN DEFAULT false,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "user_id" UUID NOT NULL,
    "title" TEXT NOT NULL DEFAULT 'Untitled Hike',
    "activity_type" TEXT NOT NULL DEFAULT 'hiking',
    "distance_km" DOUBLE PRECISION,
    "duration_seconds" INTEGER,
    "elevation_gain_m" DOUBLE PRECISION,
    "started_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "hike_tracks_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "stories" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID,
    "title" TEXT NOT NULL,
    "content" TEXT,
    "excerpt" TEXT,
    "location" TEXT,
    "country" TEXT,
    "cover_image" TEXT,
    "tags" TEXT[],
    "status" TEXT DEFAULT 'pending',
    "featured" BOOLEAN DEFAULT false,
    "author_name" TEXT,
    "author_avatar" TEXT,
    "read_time" TEXT,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "email" TEXT,
    "adventure_type" TEXT,
    "difficulty" TEXT,
    "story_content" TEXT,
    "loneliness_level" INTEGER,
    "safety_level" TEXT,
    "connectivity" TEXT,
    "aftermath" TEXT,

    CONSTRAINT "stories_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "tours" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name" TEXT NOT NULL,
    "photos" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "category" TEXT,
    "price_from" INTEGER NOT NULL DEFAULT 0,
    "currency" TEXT NOT NULL DEFAULT 'VND',
    "duration_label" TEXT,
    "cancellation_policy" TEXT,
    "pickup_included" BOOLEAN NOT NULL DEFAULT false,
    "pickup_detail" TEXT,
    "guide_languages" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "includes" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "itinerary" JSONB NOT NULL DEFAULT '[]',
    "highlights" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "full_description" TEXT,
    "is_curated" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "excludes" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "group_size_label" TEXT,

    CONSTRAINT "tours_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "curated_collections" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "title" TEXT NOT NULL,
    "subtitle" TEXT,
    "cover_image_url" TEXT,
    "is_destination" BOOLEAN NOT NULL DEFAULT true,
    "scope_value" TEXT NOT NULL,
    "rating" DECIMAL,
    "best_time_to_visit" TEXT,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "source" TEXT NOT NULL DEFAULT 'app',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "curated_collections_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trips" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "owner_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "location" TEXT NOT NULL,
    "start_date" DATE NOT NULL,
    "end_date" DATE NOT NULL,
    "budget_vnd" BIGINT NOT NULL DEFAULT 0,
    "currency" TEXT NOT NULL DEFAULT 'VND',
    "vibe" TEXT,
    "template_id" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "location_lat" DOUBLE PRECISION,
    "location_lng" DOUBLE PRECISION,
    "description" TEXT,
    "cover_image_url" TEXT,

    CONSTRAINT "trips_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_stops" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "trip_id" UUID NOT NULL,
    "day" INTEGER NOT NULL,
    "slot" TEXT NOT NULL,
    "gem_id" UUID,
    "custom_payload" JSONB,
    "price_vnd" BIGINT,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "transit_mode" TEXT,
    "transit_line" TEXT,
    "transit_duration_min" INTEGER,
    "transit_cost_vnd" BIGINT,
    "start_time" TIME,
    "notes" TEXT,
    "booking_id" UUID,

    CONSTRAINT "trip_stops_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_collaborators" (
    "trip_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "permission" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'confirmed',
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),

    CONSTRAINT "trip_collaborators_pkey" PRIMARY KEY ("trip_id","user_id")
);

-- CreateTable
CREATE TABLE "trip_blueprints" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "location" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "meta" TEXT,
    "items_json" JSONB NOT NULL,
    "save_count" INTEGER DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_blueprints_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_checklist_items" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "trip_id" UUID NOT NULL,
    "section" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "is_checked" BOOLEAN NOT NULL DEFAULT false,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "due_date_offset_days" INTEGER,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_checklist_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_category_budgets" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "trip_id" UUID NOT NULL,
    "category" TEXT NOT NULL,
    "planned_vnd" BIGINT NOT NULL DEFAULT 0,
    "updated_at" TIMESTAMPTZ(6),

    CONSTRAINT "trip_category_budgets_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_bookings" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "trip_id" UUID NOT NULL,
    "stop_id" UUID,
    "booking_type" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "confirmation_ref" TEXT,
    "provider" TEXT,
    "start_at" TIMESTAMPTZ(6),
    "end_at" TIMESTAMPTZ(6),
    "amount_vnd" BIGINT,
    "status" TEXT NOT NULL DEFAULT 'to_book',
    "created_by" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_bookings_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_documents" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "trip_id" UUID NOT NULL,
    "owner_collaborator_id" UUID,
    "type" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "file_url" TEXT,
    "expires_on" DATE,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_documents_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_packing_items" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "trip_id" UUID NOT NULL,
    "assignee_collaborator_id" UUID,
    "label" TEXT NOT NULL,
    "category" TEXT,
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "is_packed" BOOLEAN NOT NULL DEFAULT false,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_packing_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "split_groups" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name" TEXT NOT NULL,
    "description" TEXT,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "created_by" UUID,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "trip_id" UUID,

    CONSTRAINT "split_groups_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "split_group_members" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "group_id" UUID,
    "user_id" UUID,
    "display_name" TEXT,
    "avatar_url" TEXT,
    "joined_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "split_group_members_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "split_expenses" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "group_id" UUID,
    "title" TEXT NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "category" TEXT DEFAULT 'general',
    "paid_by" UUID,
    "split_type" TEXT NOT NULL DEFAULT 'equal',
    "notes" TEXT,
    "expense_date" DATE DEFAULT CURRENT_DATE,
    "created_by" UUID,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "trip_id" UUID,
    "receipt_url" TEXT,
    "is_settlement" BOOLEAN NOT NULL DEFAULT false,
    "updated_at" TIMESTAMPTZ(6),

    CONSTRAINT "split_expenses_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "split_expense_shares" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "expense_id" UUID,
    "user_id" UUID,
    "amount" DECIMAL(12,2) NOT NULL,
    "is_settled" BOOLEAN DEFAULT false,

    CONSTRAINT "split_expense_shares_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "split_settlements" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "group_id" UUID,
    "from_user" UUID,
    "to_user" UUID,
    "amount" DECIMAL(12,2) NOT NULL,
    "note" TEXT,
    "settled_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "recorded_by" UUID,

    CONSTRAINT "split_settlements_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "attractions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "owner_id" UUID NOT NULL,
    "gem_id" UUID,
    "name" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "gallery" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "address" TEXT NOT NULL,
    "latitude" DOUBLE PRECISION NOT NULL,
    "longitude" DOUBLE PRECISION NOT NULL,
    "opening_hours" TEXT NOT NULL,
    "entry_fee_type" TEXT NOT NULL,
    "entry_fee_amount" INTEGER,
    "currency" TEXT NOT NULL DEFAULT 'VND',
    "description" TEXT NOT NULL,
    "certification_urls" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "recommended_duration" TEXT,
    "verification_status" TEXT NOT NULL DEFAULT 'pending',
    "verified_by" UUID,
    "verified_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(6),

    CONSTRAINT "attractions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "restaurants" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "owner_id" UUID NOT NULL,
    "gem_id" UUID,
    "name" TEXT NOT NULL,
    "category" TEXT NOT NULL DEFAULT 'food',
    "cuisine_type" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "price_range" TEXT NOT NULL,
    "gallery" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "address" TEXT NOT NULL,
    "latitude" DOUBLE PRECISION NOT NULL,
    "longitude" DOUBLE PRECISION NOT NULL,
    "phone" TEXT NOT NULL,
    "opening_hours" TEXT NOT NULL,
    "dietary_options" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "reservation_option" BOOLEAN NOT NULL DEFAULT false,
    "business_license_url" TEXT,
    "verification_status" TEXT NOT NULL DEFAULT 'pending',
    "verified_by" UUID,
    "verified_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(6),

    CONSTRAINT "restaurants_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "restaurant_menu_items" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "restaurant_id" UUID NOT NULL,
    "dish_name" TEXT NOT NULL,
    "price_amount" INTEGER NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'VND',
    "photo_url" TEXT,
    "display_order" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "restaurant_menu_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_groups" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name" TEXT NOT NULL,
    "description" TEXT,
    "currency" TEXT DEFAULT 'USD',
    "created_by" UUID,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_groups_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_expenses" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "group_id" UUID,
    "amount" DECIMAL(10,2) NOT NULL,
    "description" TEXT,
    "paid_by" UUID,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_expenses_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_members" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "group_id" UUID,
    "user_id" UUID,
    "joined_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_members_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_settlements" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "group_id" UUID,
    "settled_by" UUID,
    "settled_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_settlements_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_saved_gems" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "gem_id" UUID NOT NULL,
    "saved_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_saved_gems_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "leaderboard_user_id_key" ON "leaderboard"("user_id");

-- CreateIndex
CREATE INDEX "saved_gems_user_id_idx" ON "saved_gems"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "gem_guides_user_id_key" ON "gem_guides"("user_id");

-- CreateIndex
CREATE INDEX "gem_guides_location_idx" ON "gem_guides" USING GIST ("location");

-- CreateIndex
CREATE INDEX "gem_guides_specialties_idx" ON "gem_guides" USING GIN ("specialties");

-- CreateIndex
CREATE INDEX "hosting_offers_guide_idx" ON "hosting_offers"("guide_id");

-- CreateIndex
CREATE INDEX "hosting_offers_type_idx" ON "hosting_offers"("type");

-- CreateIndex
CREATE INDEX "gem_saves_user_id_idx" ON "gem_saves"("user_id");

-- CreateIndex
CREATE INDEX "hike_tracks_user_id_idx" ON "hike_tracks"("user_id");

-- CreateIndex
CREATE INDEX "trip_stops_booking_id_idx" ON "trip_stops"("booking_id");

-- CreateIndex
CREATE UNIQUE INDEX "trip_collaborators_id_key" ON "trip_collaborators"("id");

-- CreateIndex
CREATE INDEX "trip_checklist_items_trip_id_idx" ON "trip_checklist_items"("trip_id");

-- CreateIndex
CREATE INDEX "trip_category_budgets_trip_id_idx" ON "trip_category_budgets"("trip_id");

-- CreateIndex
CREATE UNIQUE INDEX "trip_category_budgets_trip_id_category_key" ON "trip_category_budgets"("trip_id", "category");

-- CreateIndex
CREATE INDEX "trip_bookings_stop_id_idx" ON "trip_bookings"("stop_id");

-- CreateIndex
CREATE INDEX "trip_bookings_trip_id_idx" ON "trip_bookings"("trip_id");

-- CreateIndex
CREATE INDEX "trip_documents_trip_id_idx" ON "trip_documents"("trip_id");

-- CreateIndex
CREATE INDEX "trip_packing_items_trip_id_idx" ON "trip_packing_items"("trip_id");

-- CreateIndex
CREATE UNIQUE INDEX "split_groups_trip_id_key" ON "split_groups"("trip_id");

-- CreateIndex
CREATE INDEX "split_group_members_group_id_idx" ON "split_group_members"("group_id");

-- CreateIndex
CREATE INDEX "split_group_members_user_id_idx" ON "split_group_members"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "split_group_members_group_id_user_id_key" ON "split_group_members"("group_id", "user_id");

-- CreateIndex
CREATE INDEX "split_expenses_group_id_idx" ON "split_expenses"("group_id");

-- CreateIndex
CREATE INDEX "split_expenses_trip_id_idx" ON "split_expenses"("trip_id");

-- CreateIndex
CREATE INDEX "split_expense_shares_expense_id_idx" ON "split_expense_shares"("expense_id");

-- CreateIndex
CREATE INDEX "split_expense_shares_user_id_idx" ON "split_expense_shares"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "split_expense_shares_expense_id_user_id_key" ON "split_expense_shares"("expense_id", "user_id");

-- CreateIndex
CREATE INDEX "split_settlements_group_id_idx" ON "split_settlements"("group_id");

-- CreateIndex
CREATE UNIQUE INDEX "trip_members_group_id_user_id_key" ON "trip_members"("group_id", "user_id");

-- CreateIndex
CREATE UNIQUE INDEX "user_saved_gems_user_id_gem_id_key" ON "user_saved_gems"("user_id", "gem_id");

-- AddForeignKey
ALTER TABLE "profiles" ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "traveller_profiles" ADD CONSTRAINT "traveller_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "admin_profiles" ADD CONSTRAINT "admin_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "admin_action_log" ADD CONSTRAINT "admin_action_log_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "leaderboard" ADD CONSTRAINT "leaderboard_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "saved_gems" ADD CONSTRAINT "saved_gems_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "saved_gems" ADD CONSTRAINT "saved_gems_profiles_fkey" FOREIGN KEY ("user_id") REFERENCES "profiles"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "gem_guides" ADD CONSTRAINT "gem_guides_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "profiles"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "hosting_offers" ADD CONSTRAINT "hosting_offers_guide_id_fkey" FOREIGN KEY ("guide_id") REFERENCES "gem_guides"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "gem_saves" ADD CONSTRAINT "gem_saves_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "gem_saves" ADD CONSTRAINT "gem_saves_gem_id_fkey" FOREIGN KEY ("gem_id") REFERENCES "saved_gems"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "hike_tracks" ADD CONSTRAINT "hike_tracks_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "stories" ADD CONSTRAINT "stories_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trips" ADD CONSTRAINT "trips_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_stops" ADD CONSTRAINT "trip_stops_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_stops" ADD CONSTRAINT "trip_stops_gem_id_fkey" FOREIGN KEY ("gem_id") REFERENCES "saved_gems"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_stops" ADD CONSTRAINT "trip_stops_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "trip_bookings"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_collaborators" ADD CONSTRAINT "trip_collaborators_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_collaborators" ADD CONSTRAINT "trip_collaborators_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_checklist_items" ADD CONSTRAINT "trip_checklist_items_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_category_budgets" ADD CONSTRAINT "trip_category_budgets_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_bookings" ADD CONSTRAINT "trip_bookings_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_bookings" ADD CONSTRAINT "trip_bookings_stop_id_fkey" FOREIGN KEY ("stop_id") REFERENCES "trip_stops"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_bookings" ADD CONSTRAINT "trip_bookings_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_documents" ADD CONSTRAINT "trip_documents_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_documents" ADD CONSTRAINT "trip_documents_owner_collaborator_id_fkey" FOREIGN KEY ("owner_collaborator_id") REFERENCES "trip_collaborators"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_packing_items" ADD CONSTRAINT "trip_packing_items_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_packing_items" ADD CONSTRAINT "trip_packing_items_assignee_collaborator_id_fkey" FOREIGN KEY ("assignee_collaborator_id") REFERENCES "trip_collaborators"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "split_groups" ADD CONSTRAINT "split_groups_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "split_groups" ADD CONSTRAINT "split_groups_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "split_group_members" ADD CONSTRAINT "split_group_members_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "split_groups"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "split_group_members" ADD CONSTRAINT "split_group_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "split_expenses" ADD CONSTRAINT "split_expenses_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "split_groups"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "split_expenses" ADD CONSTRAINT "split_expenses_paid_by_fkey" FOREIGN KEY ("paid_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "split_expenses" ADD CONSTRAINT "split_expenses_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "split_expenses" ADD CONSTRAINT "split_expenses_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "split_expense_shares" ADD CONSTRAINT "split_expense_shares_expense_id_fkey" FOREIGN KEY ("expense_id") REFERENCES "split_expenses"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "split_expense_shares" ADD CONSTRAINT "split_expense_shares_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "split_settlements" ADD CONSTRAINT "split_settlements_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "split_groups"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "split_settlements" ADD CONSTRAINT "split_settlements_from_user_fkey" FOREIGN KEY ("from_user") REFERENCES "auth"."users"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "split_settlements" ADD CONSTRAINT "split_settlements_to_user_fkey" FOREIGN KEY ("to_user") REFERENCES "auth"."users"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "split_settlements" ADD CONSTRAINT "split_settlements_recorded_by_fkey" FOREIGN KEY ("recorded_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "attractions" ADD CONSTRAINT "attractions_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "attractions" ADD CONSTRAINT "attractions_gem_id_fkey" FOREIGN KEY ("gem_id") REFERENCES "saved_gems"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "attractions" ADD CONSTRAINT "attractions_verified_by_fkey" FOREIGN KEY ("verified_by") REFERENCES "auth"."users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "restaurants" ADD CONSTRAINT "restaurants_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "restaurants" ADD CONSTRAINT "restaurants_gem_id_fkey" FOREIGN KEY ("gem_id") REFERENCES "saved_gems"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "restaurants" ADD CONSTRAINT "restaurants_verified_by_fkey" FOREIGN KEY ("verified_by") REFERENCES "auth"."users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "restaurant_menu_items" ADD CONSTRAINT "restaurant_menu_items_restaurant_id_fkey" FOREIGN KEY ("restaurant_id") REFERENCES "restaurants"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_groups" ADD CONSTRAINT "trip_groups_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_expenses" ADD CONSTRAINT "trip_expenses_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "trip_groups"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_expenses" ADD CONSTRAINT "trip_expenses_paid_by_fkey" FOREIGN KEY ("paid_by") REFERENCES "auth"."users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_members" ADD CONSTRAINT "trip_members_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "trip_groups"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_members" ADD CONSTRAINT "trip_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_settlements" ADD CONSTRAINT "trip_settlements_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "trip_groups"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "trip_settlements" ADD CONSTRAINT "trip_settlements_settled_by_fkey" FOREIGN KEY ("settled_by") REFERENCES "auth"."users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "user_saved_gems" ADD CONSTRAINT "user_saved_gems_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "user_saved_gems" ADD CONSTRAINT "user_saved_gems_gem_id_fkey" FOREIGN KEY ("gem_id") REFERENCES "saved_gems"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
