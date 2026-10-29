# ExploriFe Migration Plan: Flutter/Supabase → Next.js/Prisma/PostgreSQL

Status: **Step 1 (Audit), Step 2 (Foundation), and Step 3 (Database) approved
and done, with the decisions in §0 below.** `prisma/schema.prisma` was
hand-built from live-DB SQL introspection (see §7); `prisma generate`/
`tsc`/`npm run build` all pass against it. The `0_init` baseline and the
`1_hike_tracks_fields` migration have both been applied against the live
database (locally, by the user — `prisma migrate status` reports clean, no
drift) and the `auth.uid()`-trigger protections are live in
`lib/auth/permissions.ts` with passing unit tests. See §7's Step 3 writeup
for the full record.

This document is the full audit of the existing ExploriFe app (Flutter + Supabase)
required before any new-stack code is written.

Target stack: Next.js (App Router, TypeScript, strict mode), Tailwind CSS,
PostgreSQL (the **existing** Supabase-hosted Postgres instance — not a new
database), Prisma ORM, Server Components + Server Actions + zod validation.

---

## 0. Architecture Decisions (Approved)

These decisions were made after reviewing the §6 risks below and supersede
anything in the rest of this document that assumed a clean-slate backend.

- **The existing Supabase project is kept as infrastructure.** Postgres is
  accessed via Prisma; Supabase Auth is used via `@supabase/ssr` (including
  anonymous sessions and identity linking — see decision on Risk #8); Supabase
  Storage keeps the `gem-photos` and `trip-covers` buckets (Risk #7); Realtime
  is deferred (Risk #9). **No Auth.js. No data migration. No new storage
  provider.**
- **The Flutter app may still read/write this same database** during and after
  the transition. No existing table or column may be renamed or dropped without
  being listed here for explicit approval first. Prisma model names that differ
  from the underlying SQL identifiers use `@@map` / `@map` so the live schema
  is untouched.
- **Prisma connects with elevated privileges and bypasses RLS.** All
  authorization must be enforced in application code — centralized in
  `lib/auth/permissions.ts` — and that module must be called from every Server
  Action and Route Handler that touches the database. RLS stays **enabled** on
  every table as defense-in-depth (e.g. against a leaked low-privilege key, a
  future direct-PostgREST caller, or a bug that bypasses the TS permission
  layer) but is not relied upon as the primary gate from the Next.js app.
- **Two connection strings**: `DATABASE_URL` — the pooled connection (PgBouncer,
  for normal query traffic) — and `DIRECT_URL` — the direct connection (for
  `prisma migrate`, which needs a non-pooled session). Both point at the same
  existing database.

---

## 1. Pages / Routes

The current app uses `go_router` with one `ShellRoute` (persistent bottom nav) plus
several full-screen/overlay routes. Every session starts as an **anonymous guest**
(Supabase anonymous auth) — there is no global sign-in gate. Individual *write*
actions gate on a real (non-guest) account via a `requireAccount()` sheet, not at
the router level. 47 unique routes total (+ a 404 fallback).

### Auth
| Route | Screen | Auth | Description |
|---|---|---|---|
| `/auth` | AuthScreen | none | Voluntary sign-in page (Google OAuth button). `?redirect=` optional destination. |
| `/auth/callback` | AuthCallbackScreen | none | OAuth/GoTrue redirect handler. Reads `code` / `error` / `error_code` / `error_description`. |

### Main (bottom-nav shell)
| Route | Screen | Auth | Description |
|---|---|---|---|
| `/home` | HomeScreen | guest ok | Featured gems rail, Explore Ideas rail (category chips), search bar, saved gems/trips if signed in. |
| `/explore` | ExploreScreen | guest ok | Map-based destination browser (native: outdoors/dark style; web: Mapbox standard). |
| `/explore-ideas` | ExploreIdeasScreen | guest ok | Full unfiltered curated-collection list. `?category=` preselects a chip. |
| `/listings` | ListingsScreen | guest ok | Unified search across Destinations / Gems / Tours tabs. `?category=`, `extra:true` (autofocus search). |
| `/listings/:id` | DestinationDetailScreen | guest ok | Mapbox POI detail (name, address, static map, nearby POIs via Tilequery). `:id` = mapbox_id. |
| `/destinations/explore` | DestinationLandingScreen | guest ok | City landing: gems scoped to city (substring match on `gem_location`), category chips, "Plan a trip" CTA → `/trips/new`. `name`, `lat`, `lng` query params. |
| `/profile` | ProfileScreen | guest ok (tabs below vary) | Tabbed profile shell — see breakdown below. `?tab=N` or `extra: ProfileDeepLink(tab, tripId, segment)`. |
| `/gems/:id` | GemDetailScreen | guest ok | Gem detail (photos, location, category, amenities). "Add to trip" CTA requires real account. |
| `/tours` | ToursListScreen | guest ok | List of bookable priced tours/experiences. |
| `/tours/:id` | TourDetailScreen | guest ok | Tour detail page. |
| `/stories` | StoriesScreen | guest ok | Feed of approved user travel stories. |
| `/stories/:id` | StoryDetailScreen | guest ok | Single story detail. |
| `/trips/:id/builder` | TripBuilderScreen | real account | Drag-drop itinerary builder across days; auto-saves. `?day=N` optional. |

### Overlays / modals (no bottom nav)
| Route | Screen | Auth | Description |
|---|---|---|---|
| `/drop-gem` | PlacementScreen | real account | Full-screen map, fixed center pin = gem coordinate. `extra:{lat,lng}` optional initial center. |
| `/submit-story` | SubmitStoryScreen | real account | Story submission form (title, email, location, content, adventure type, difficulty, loneliness/safety/connectivity/aftermath). |
| `/trips` | TripsListScreen | guest ok | All trips bucketed Active-Soon / Upcoming / Past. |
| `/trips/new` | TripSetupSheet | real account | 2-step modal: destination, then travelers. `?location=`, `?lat=`, `?lng=` prefill. |
| `/trips/:id`, `/trips/:id/summary` | TripSummaryScreen | guest ok (RLS scopes data to owner) | Trip dashboard: overview, spend breakdown, planned vs actual, task checklist, expense donut. |
| `/hikes` | HikesScreen | guest ok | Activity log list. |
| `/log-hike` | LogHikeScreen | real account | Log activity: title, distance, elevation, duration, type. |
| `/splits` | SplitsScreen | guest ok | Expense-split group list/dashboard. |
| `/splits/:id` | SplitDetailScreen | guest ok (RLS scopes to members) | Split group detail: expenses, settlement calculator, member breakdown. |

### Business listings (create/edit/moderate)
| Route | Screen | Auth | Description |
|---|---|---|---|
| `/attractions/new`, `/attractions/:id/edit` | AttractionFormScreen | Business Owner (+ ownership on edit) | Create/edit attraction: gallery, geocoded address, hours, entry fee, amenities, optional gem link. |
| `/attractions/:id` | AttractionDetailScreen | guest ok | Approved attraction detail. |
| `/attractions/moderation` | AttractionModerationScreen | Content Moderator / Regional Admin / Super Admin | Pending-attraction approve/reject queue. |
| `/restaurants/new`, `/restaurants/:id/edit` | RestaurantFormScreen | Business Owner (+ ownership on edit) | Create/edit restaurant: cuisine tags, dietary options, gallery, geocoded address, hours, reservation flag, license URL. |
| `/restaurants/:id` | RestaurantDetailScreen | guest ok | Approved restaurant detail. |
| `/restaurants/moderation` | RestaurantModerationScreen | Content Moderator / Regional Admin / Super Admin | Pending-restaurant approve/reject queue. |

### `/profile` tabs (index-based)
0. **Overview** — trip stats, active/upcoming trip card, badges, quick actions
1. **My Trip** — active trip itinerary/overview/checklist/budget (`TripDetailSegment`)
2. **Saved Gems** — saved gems (persistence not yet implemented — "coming soon")
3. **My Stories** — user's own submitted stories
4. **Badges** — achievement badges
5. **Settings** — account, privacy, notifications, theme

### Route-level notes
- No forced auth gate on launch; every new session is anonymous-guest by default.
- Role-gated routes rely on `profiles.role` (`business_owner` for listing CRUD;
  `content_moderator` / `regional_admin` / `super_admin` for moderation).
- `/auth/callback` has special handling for `identity_already_exists`; a router
  `errorBuilder` re-routes stray GoTrue redirects that land on the bare site URL
  back into `/auth/callback`.

### Routing change for the new stack — approved
`/profile?tab=N` (and the `ProfileDeepLink(tab, tripId, segment)` extra used for
the My Trip tab) is replaced by real nested routes. Query-param tab selection
and the index-based deep link are both Flutter-router conventions that don't
belong in a URL-first Next.js app.

| Old | New |
|---|---|
| `/profile` or `/profile?tab=0` | `/profile/overview` |
| `/profile?tab=1` (My Trip, no deep link) | `/profile/trips/[tripId]/overview` — `tripId` resolved server-side to the user's active trip when not explicitly known |
| `ProfileDeepLink(tab: 1, tripId, segment: 'itinerary'\|'overview'\|'checklist'\|'budget')` | `/profile/trips/[tripId]/itinerary`, `/profile/trips/[tripId]/overview`, `/profile/trips/[tripId]/checklist`, `/profile/trips/[tripId]/budget` |
| `/profile?tab=2` | `/profile/saved` |
| `/profile?tab=3` | `/profile/stories` |
| `/profile?tab=4` | `/profile/badges` |
| `/profile?tab=5` | `/profile/settings` |

`/profile` itself redirects to `/profile/overview`; each bare `?tab=N` value
gets a redirect to its new path for any old links still in circulation (emails,
bookmarks, the edge function's invite-redirect base). The top-level
`/trips/:id` / `/trips/:id/summary` trip-dashboard routes are a separate,
already-URL-addressable feature (`TripSummaryScreen`) and are **not** part of
this change — only the tab-index-driven Profile shell is being replaced.

---

## 2. API Endpoints (Supabase call-sites)

The Flutter app has **no custom REST/GraphQL API layer** — it talks to Postgres
directly through the Supabase client (table CRUD under RLS, Postgres RPC
functions, Storage, and one Edge Function). In Next.js these all become **Server
Actions / Route Handlers** backed by Prisma + application-level auth checks.

### 2.1 Auth operations (Supabase Auth, `lib/providers/auth_provider.dart`)
- `signInWithGoogle()` — OAuth, links to the current anonymous session if guest
- `signInWithGoogleDirect()` — OAuth, replaces the anonymous session
- `signInWithGitHub()` — OAuth sign-in
- `signInAsGuest()` — `auth.signInAnonymously()`
- `signOut()`
- `onAuthStateChange` session listener; `currentSession` getter

### 2.2 Table operations, by provider/repository

**AuthProvider** — `profiles` select/update (display_name, username); RPC
`find_user_by_identifier` (public, security definer); `admin_profiles` update
(last_login/ip, best-effort).

**GemRepository** (backs GemProvider) — `saved_gems` select (public feed filtered
`source='sheet_sync'`, by id, related-by-category), insert (auth required,
includes `photo_urls[]`/`photo_captions`); Storage upload to `gem-photos` bucket;
`gem_saves` select/upsert/delete (auth required, scoped to `auth.uid()`); realtime
channel `public-saved-gems` (insert/delete, filtered).

**TripProvider** — direct client access (not repository-wrapped). `trips`
select/insert/update (owner-scoped); `trip_stops` select/insert/update/delete/
reorder (by trip, batch operations for reorder/duplicate-day/delete-day);
`trip_checklist_items` select/insert/update; `trip_category_budgets` select/
upsert; `trip_blueprints` select (public catalog, no auth); `trip_collaborators`
insert/upsert (owner + traveler rows at trip creation); Storage upload to
`trip-covers` bucket. All mutations auth-required.

**BookingRepository** — `trip_bookings` select (by trip, RLS-scoped)/insert/
update/delete. All auth-required.

**StoryProvider** — `stories` select (approved-only public feed; by id requiring
approved; own stories by email, auth required); insert (auth required, starts
`status='pending'`); realtime channel `public-stories` (insert/update/delete,
non-approved filtered client-side).

**HikeProvider** — `hike_tracks` select (own, limit 50)/insert. Auth required.
⚠️ See Risk #1 — this feature is currently broken (column mismatch).

**SplitsProvider** — `split_groups`, `split_group_members`, `split_expenses`,
`split_expense_shares`, `split_settlements` select/insert, all auth-required and
member-scoped; RPC `get_or_create_trip_split_group` (security definer, atomic).

**TripSetupProvider** — `trip_documents`, `trip_packing_items` select/insert/
delete/update (toggle packed); `trip_collaborators` insert (add traveler);
`profiles` embed for collaborator names/avatars. Auth required.

**TourRepository** — `tours` select (public feed + by id). No auth.

**CuratedCollectionRepository** — `curated_collections` select (public, ordered
`sort_order`). No auth.

**AttractionRepository** — `attractions` select (verified public / by id / by gem
/ owned-by-me / pending-for-moderation); insert/update (owner, auth required); RPC
`verify_attraction`, `retract_attraction` (security definer, admin/owner).

**RestaurantRepository** — `restaurants` select (same shape as attractions);
insert/update (owner); RPC `verify_restaurant`, `retract_restaurant`;
`restaurant_menu_items` select/replace (delete-all + batch insert, owner-only).

**Requirement for the future listing-forms feature** (`/attractions/new`,
`/restaurants/new` from §1 — not yet built): the Prisma-side `createAttraction()`/
`createRestaurant()` Server Actions that back those forms must, like
`updateProfile()`/`updateUserRole()` in `lib/server/profiles.ts`, not just trust
client input. Specifically they must (1) `requireRole('business_owner')` — reject
anyone else before touching the DB; (2) set `owner_id` from the authenticated
session (`requireUser().id`), never accept it as a field on the incoming patch;
and (3) force `verificationStatus: 'pending'` server-side on every insert,
ignoring/stripping any `verificationStatus`/`verifiedBy`/`verifiedAt` the client
sends — mirroring the existing "superseded" guard on those same columns for
*updates* noted in the `lock_attraction_verification_fields` /
`lock_restaurant_verification_fields` row of the RPC table below. Not built yet;
this is a landing requirement for whoever implements those two functions.

**AdminProfileRepository** — `admin_profiles` select by id, upsert, login-record
update.

**AdminUserRepository** — RPC `admin_list_users` (paginated, search, role
filter), `admin_role_counts`, `admin_update_user_role` (super_admin only, DB
re-verifies); Edge Function `admin-create-user` (create + `resend_invite`
actions).

**AdminActionLogRepository** — `admin_action_log` insert/select/count (auth
audit trail).

**TravellerProfileRepository** — `traveller_profiles` select/upsert; delegates
wishlist to `GemRepository.fetchSavedGems()`; `trips`+`trip_bookings` join for
booking history; reviews-written is a stub (always `[]` — no reviews feature
exists).

### 2.3 Postgres RPC functions (all `SECURITY DEFINER` — see Risk #3)
`find_user_by_identifier`, `admin_list_users`, `admin_role_counts`,
`admin_update_user_role`, `admin_create_user_profile`, `admin_log_resend_invite`,
`verify_attraction`, `retract_attraction`, `verify_restaurant`,
`retract_restaurant`, `get_or_create_trip_split_group`, `create_split_group`,
`is_admin`, `is_super_admin`, `is_guide`, `is_content_admin`, `is_group_member`,
`is_trip_owner`, `handle_new_user` (likely an `auth.users` insert trigger target),
`lock_profile_role_field`, `lock_attraction_verification_fields`,
`lock_restaurant_verification_fields`, `increment_gems_score`,
`increment_journal_score`. Three content-sync RPCs referenced in memory but not
re-verified in this pass: `upsert_gem_from_sheet`, `upsert_tour_from_sheet`,
`upsert_curated_collection_from_sheet` (Google-Sheets content pipeline).

### 2.4 Edge Function — `admin-create-user` (Deno, `supabase/functions/admin-create-user/index.ts`)
Single HTTP function, two actions, both `POST`, both require `Authorization`
header (caller's JWT) and `profiles.role === 'super_admin'`:

- **Create user** (default action)
  - Input: `{ full_name, email, username?, role }`
  - Validates email format, role against an allow-list of 7 roles, username
    format (`^[a-z0-9_]{3,20}$`); pre-checks username uniqueness
  - Calls `serviceClient.auth.admin.inviteUserByEmail()` (service-role key,
    redirect to `${APP_URL}/auth/callback`), then `callerClient.rpc('admin_create_user_profile', ...)`
  - On profile-creation failure, rolls back by deleting the just-invited auth user
  - Output: `{ user: <profile row> }` (200) or `{ error }` (400/403/409/500)
- **Resend invite** (`action: 'resend_invite'`)
  - Input: `{ action: 'resend_invite', user_id }`
  - Looks up the target user server-side (email never trusted from client),
    rejects if already confirmed, re-invites, best-effort logs via
    `admin_log_resend_invite`
  - Output: `{ ok: true }` (200) or `{ error }` (400/404/409/500)

Env vars read: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`,
`APP_URL` (defaults to `https://explorife2.vercel.app`).

### 2.5 Other deployed Edge Functions (not reviewed — see Risk #4)
`qa-role-check-harness`, `qa-username-gen-harness`, `qa-traveler-session-harness`,
`qa-username-taken-check` — all present in the live project per
`list_edge_functions`, but **no source found in the repo** under
`supabase/functions/`. Likely QA/test scaffolding deployed ad hoc and not
version-controlled.

### 2.6 Storage buckets
`gem-photos` (public read), `trip-covers` (public read) — both allow
owner-scoped write per the RLS policies on `storage.objects` (see advisories in
§6). An `avatar`-related policy set also exists on `storage.objects`
(`avatar_public_read`, `avatar_update_own`) though no avatar-upload call-site was
found in the providers/services sweep — worth confirming before dropping it from
the new schema.

### 2.7 Realtime
Two Postgres Changes channels: `public-saved-gems` (insert/delete on
`saved_gems`, filtered to `source='sheet_sync'`) and `public-stories`
(insert/update/delete on `stories`, non-approved rows filtered client-side).
Next.js has no built-in equivalent — needs SSE, a WebSocket layer, or polling.

---

## 3. Data Model

36 tables in the live `public` schema (project `yshgjzmyapdepkapodno`, Postgres
17.6.1). All app tables use `uuid` primary keys (`gen_random_uuid()`, two tables
use `extensions.uuid_generate_v4()` instead — no functional difference). Every
`auth.users.id` foreign key points at Supabase's own `auth` schema, which Prisma
cannot reference directly — the new schema needs its own `User` table that these
all repoint to.

### Gems / Content
- **saved_gems** (33 rows) — the actual "Gem" entity despite the table name. id,
  user_id→profiles/auth.users (nullable), gem_name, gem_location, category,
  gem_coords (jsonb), saved_at, best_time_to_visit, difficulty, description,
  photo_url, gem_type (default 'gem'), tagline, est_duration_min,
  photo_urls (text[]), photo_captions (jsonb), good_to_know (text[]),
  source (default 'app' — sheet-synced rows use `'sheet_sync'`).
- **gem_guides** (6) — id, user_id→profiles, specialties (guide_specialty[]
  enum), rating, total_hosted, verified, latitude/longitude, location
  (PostGIS geography, computed from lat/lng), available, created/updated_at.
- **hosting_offers** (16) — id, guide_id→gem_guides, title, type (**resolved**:
  reuses the `guide_specialty` enum — the same 8 values as `gem_guides.specialties`,
  not a distinct type), description, capacity, duration_hours, is_active,
  created/updated_at.
- **gem_saves** (0) — composite PK (user_id, gem_id)→auth.users/saved_gems,
  saved_at. Live "save a gem" join table per GemRepository.
- **user_saved_gems** (0) — **excluded from the Prisma schema per Risk #2's
  decision** (see §6) — near-duplicate of `gem_saves`, no Flutter/migration
  call-site references it. Note it does still carry a live DB trigger
  (`on_gem_saved` → `increment_gems_score()`, identical to the one on
  `saved_gems`) that would fire if anything ever inserted into it — harmless
  today since nothing does, but it means the table isn't *fully* inert at the
  database level, only at the application level. Left in place in the live DB,
  just not modeled in Prisma.
- **hike_tracks** (0) — id, name, route (jsonb), featured, created_at,
  user_id→auth.users. ⚠️ Known broken: `HikeProvider` reads/writes columns
  (`title`, `activity_type`, `distance_km`, `duration_seconds`,
  `elevation_gain_m`, `started_at`) that don't exist on this table — see Risk #1.
- **stories** (21) — id, user_id→auth.users, title, content, excerpt, location,
  country, cover_image, tags (text[]), status (default 'pending'), featured,
  author_name, author_avatar, read_time, created/updated_at, email,
  adventure_type, difficulty, story_content, loneliness_level, safety_level,
  connectivity, aftermath.
- **tours** (4) — id, name, photos (text[]), category, price_from, currency
  (default 'VND'), duration_label, cancellation_policy, pickup_included,
  pickup_detail, guide_languages (text[]), includes/excludes (text[]),
  itinerary (jsonb), highlights (text[]), full_description, is_curated,
  group_size_label, created_at.
- **curated_collections** (4) — id, title, subtitle, cover_image_url,
  is_destination, scope_value, rating, best_time_to_visit, sort_order,
  source (default 'app'), created_at.

### People / Profiles
- **profiles** (67) — id→auth.users (PK), name, avatar_url, bio, city, country,
  languages (text[]), display_name, privacy_show_gps, privacy_blur_maps,
  username, role (`user_role` enum: traveler / guide / business_owner /
  content_moderator / regional_admin / super_admin / finance_admin), created/updated_at.
- **traveller_profiles** (1) — user_id→auth.users (PK), date_of_birth, gender,
  nationality, phone, login_method, preferred_language, account_status
  (default 'active'), interests (text[]), travel_style, budget_range,
  home_location, verification_status (default 'unverified'),
  emergency_contact, created/updated_at.
- **admin_profiles** (1) — user_id→auth.users (PK), role_title,
  managed_profile_types (text[]), assigned_region, account_status,
  two_factor_enabled, last_login, last_login_ip, notes, created/updated_at.
- **admin_action_log** (10) — id, actor_id→auth.users (nullable, survives actor
  deletion), action_type, target_profile_id (uuid, no FK), details (jsonb),
  created_at, old_role/new_role (user_role enum).
- **leaderboard** (8) — id, user_id→auth.users, display_name, avatar_url,
  gems_discovered, journals_written, countries_visited, total_saves,
  rank_score (generated: gems*3 + journals*5 + countries*10 + saves), updated_at.

### Trips
- **trips** (19) — id, owner_id→auth.users, name, location, start_date,
  end_date, budget_vnd (bigint), currency (default 'VND'), vibe,
  template_id (uuid, no FK), location_lat/lng, description, cover_image_url,
  created_at.
- **trip_stops** (27) — id, trip_id→trips, day, slot, gem_id→saved_gems
  (nullable), custom_payload (jsonb), price_vnd, sort_order, transit_mode,
  transit_line, transit_duration_min, transit_cost_vnd, start_time, notes,
  booking_id→trip_bookings (nullable).
- **trip_collaborators** (21) — composite PK (trip_id, user_id)→trips/auth.users,
  permission, status (default 'confirmed'), plus a secondary surrogate `id`
  (not the PK — worth normalizing to a single uuid PK in Prisma).
- **trip_blueprints** (0) — id, location, title, meta, items_json (jsonb),
  save_count, created_at. Public catalog (no owner FK), seeds new trips.
- **trip_checklist_items** (0) — id, trip_id→trips, section, title, is_checked,
  sort_order, due_date_offset_days, created_at.
- **trip_category_budgets** (76) — id, trip_id→trips, category, planned_vnd,
  updated_at.
- **trip_bookings** (2) — id, trip_id→trips, stop_id→trip_stops (nullable),
  booking_type, title, confirmation_ref, provider, start_at/end_at, amount_vnd,
  status (default 'to_book'), created_by→auth.users, created_at.
- **trip_documents** (0) — id, trip_id→trips,
  owner_collaborator_id→trip_collaborators (nullable), type, title, file_url,
  expires_on, created_at.
- **trip_packing_items** (0) — id, trip_id→trips,
  assignee_collaborator_id→trip_collaborators (nullable), label, category,
  quantity, is_packed, sort_order, created_at.

### Splits (expense-splitting — active)
- **split_groups** (22) — id, name, description, currency (default 'USD'),
  created_by→auth.users, trip_id→trips (nullable), created/updated_at.
- **split_group_members** (26) — id, group_id→split_groups,
  user_id→auth.users, display_name, avatar_url, joined_at.
- **split_expenses** (12) — id, group_id→split_groups, title, amount
  (numeric), currency, category (default 'general'), paid_by→auth.users,
  split_type (default 'equal'), notes, expense_date, created_by→auth.users,
  trip_id→trips (nullable), receipt_url, is_settlement, created/updated_at.
- **split_expense_shares** (2) — id, expense_id→split_expenses,
  user_id→auth.users, amount, is_settled.
- **split_settlements** (1) — id, group_id→split_groups, from_user→auth.users,
  to_user→auth.users, amount, note, settled_at, recorded_by→auth.users.

### Legacy/parallel splitting tables — excluded from Prisma schema (Risk #2, resolved)
`trip_groups`, `trip_expenses`, `trip_members`, `trip_settlements` — 0 rows
each, no Flutter/migration/function/trigger references found anywhere (see §6
Risk #2 findings). Fully dead at both the application and database level.
Excluded from the Prisma schema; left in place in the live DB, not dropped.

### Local-business listings
- **attractions** (0) — id, owner_id→auth.users, gem_id→saved_gems (nullable),
  name, category, gallery (text[]), address, latitude/longitude,
  opening_hours, entry_fee_type, entry_fee_amount, currency (default 'VND'),
  description, certification_urls (text[]), recommended_duration,
  verification_status (default 'pending'), verified_by→auth.users, verified_at,
  deleted_at (soft delete), created/updated_at.
- **restaurants** (0) — id, owner_id→auth.users, gem_id→saved_gems (nullable),
  name, category (default 'food'), cuisine_type (text[]), price_range,
  gallery (text[]), address, latitude/longitude, phone, opening_hours,
  dietary_options (text[]), reservation_option, business_license_url,
  verification_status (default 'pending'), verified_by→auth.users, verified_at,
  deleted_at, created/updated_at.
- **restaurant_menu_items** (0) — id, restaurant_id→restaurants, dish_name,
  price_amount, currency (default 'VND'), photo_url, display_order, created_at.

### System (exclude from Prisma schema)
- **spatial_ref_sys** (8,500 rows) — PostGIS system table, RLS **disabled**
  (flagged by the security linter — see Risk #6). Not app data.

### Enums
- `user_role`: traveler, guide, business_owner, content_moderator,
  regional_admin, super_admin, finance_admin
- `guide_specialty`: hidden_gems, food_tour, city_walk, coffee_chat, night_life,
  street_art, nature, photography — used by both `gem_guides.specialties`
  (array) and `hosting_offers.type` (single value; confirmed via
  `information_schema.columns.udt_name`, resolving Risk #5 — it is not a
  separate type).

### PostGIS columns (generated columns & triggers to carry over as raw SQL)
- `gem_guides.location` is a `geography(Point)` column, generated from
  `latitude`/`longitude` — Prisma has no native geography type, so this field
  must be declared with `Unsupported("geography(Point,4326)")` in
  `schema.prisma` (unqueryable through the Prisma Client API; any geo query
  against it needs `prisma.$queryRaw`).
- Database triggers that are **not** being ported to TypeScript because they
  don't implement authorization (pure data-consistency/bookkeeping — safe to
  leave running exactly as-is under Prisma writes): `gem_guides_updated_at`,
  `hosting_offers_updated_at`, `profiles_updated_at` (all `set_updated_at()`);
  `set_split_expenses_updated_at`, `set_trip_category_budgets_updated_at`,
  `set_trip_checklist_updated_at` (all `moddatetime('updated_at')`);
  `split_groups_updated_at` (`handle_updated_at()`);
  `trip_checklist_items_sort_order` (`set_trip_checklist_sort_order()`);
  `on_profile_update` → `sync_leaderboard_name()`; `on_gem_saved` (on both
  `saved_gems` and the excluded `user_saved_gems`) → `increment_gems_score()`;
  `on_story_approved` → `increment_journal_score()` (registered twice on
  `stories` under the same trigger name — a pre-existing duplicate, not
  introduced by this migration; harmless since it just double-fires the same
  idempotent-ish increment, flagging for awareness only). None of these read
  `auth.uid()`, so they behave identically regardless of whether the write came
  from Supabase's PostgREST or Prisma's direct connection.
- Triggers that **do** read `auth.uid()` and therefore need special handling —
  see Risk #3 in §6, they are the reason the authorization logic is being
  reimplemented in TypeScript rather than left to the database:
  `profiles_lock_role_field` (`lock_profile_role_field()`),
  `attractions_lock_verification_fields`
  (`lock_attraction_verification_fields()`),
  `restaurants_lock_verification_fields`
  (`lock_restaurant_verification_fields()`).

### Money-field convention carried over
All monetary columns in the live schema are `bigint`/`numeric` minor-unit-ish
fields (`*_vnd` columns are whole VND, which has no subunit) rather than
`Float` — this already matches the target convention ("money as Decimal or
integer minor units, never Float, with a currency field"), so the Prisma schema
should preserve `Decimal`/`BigInt` + a sibling `currency` column per table
exactly as‑is.

---

## 3a. Authorization Migration Map (SECURITY DEFINER → TypeScript)

Every Postgres function flagged by the security advisor as `SECURITY DEFINER`
(27 in `public`, excluding PostGIS's own `st_estimatedextent` overloads and the
3 content-sync `upsert_*_from_sheet` functions, which are out of scope per
Risk #10) is accounted for below. **All of them read `auth.uid()`** (directly,
or indirectly via `is_super_admin()`/`is_admin()`/etc.), which resolves from
Supabase's `request.jwt.claims` session GUC — a value **only PostgREST sets
per-request**. Prisma's direct connection never sets it, so `auth.uid()` is
always `NULL` in any session Prisma opens. Concretely this means:

- None of these functions can simply be "called via Prisma" — they'd silently
  behave as an unauthenticated caller every time.
- The three trigger-form versions (`lock_profile_role_field`,
  `lock_attraction_verification_fields`, `lock_restaurant_verification_fields`)
  fire on **every** UPDATE regardless of client, and with `auth.uid()` always
  `NULL` under Prisma they will deterministically **revert** `profiles.role`,
  and `attractions`/`restaurants`' `verification_status`/`verified_by`/
  `verified_at` back to their old values on every Prisma-driven UPDATE that
  touches those columns — i.e. without a code change, role assignment and
  listing verification would silently stop working the moment writes move to
  Prisma. This is flagged as an open question in §6 (Risk #3) rather than
  fixed here, since altering/dropping a trigger on a live table needs the same
  approval as any other schema change.

| Postgres function | New TypeScript home | Permission check (`lib/auth/permissions.ts`) |
|---|---|---|
| `admin_create_user_profile` | `lib/server/admin/users.ts` → `createUserProfile()`, called from the "New User" Server Action alongside the Supabase Auth Admin `inviteUserByEmail` call (same two-client split as today's edge function) | `requireRole('super_admin')`; port the "fresh pending invite only" guard, username dedupe/derivation loop, and `admin_action_log` insert verbatim |
| `admin_list_users` | `lib/server/admin/users.ts` → `listUsers()` | `requireRole(['content_moderator','regional_admin','super_admin','finance_admin'])` |
| `admin_log_resend_invite` | `lib/server/admin/users.ts` → `logResendInvite()` | `requireRole('super_admin')` |
| `admin_role_counts` | `lib/server/admin/users.ts` → `getRoleCounts()` | `requireRole(['content_moderator','regional_admin','super_admin','finance_admin'])` |
| `admin_update_user_role` | `lib/server/admin/users.ts` → `updateUserRole()` | `requireRole('super_admin')`; port "can't role an anonymous session" and "can't demote the last super_admin" guards verbatim |
| `create_split_group` | `lib/server/splits/groups.ts` → `createSplitGroup()` | `requireAuth()` (open question: should a guest/anonymous session be allowed to create a split group? today's RLS allows `anon`/`authenticated` both — carry the same breadth unless told otherwise) |
| `find_user_by_identifier` | `lib/server/users/lookup.ts` → `findUserByIdentifier()` | `requireAuth()` |
| `get_or_create_trip_split_group` | `lib/server/splits/groups.ts` → `getOrCreateTripSplitGroup()` | `requireTripAccess(tripId)` (owner or collaborator — uses `isTripOwner`/collaborator-lookup primitives below) |
| `verify_attraction` | `lib/server/listings/attractions.ts` → `verifyAttraction()` | `requireRole(['content_moderator','regional_admin','super_admin'])` |
| `retract_attraction` | `lib/server/listings/attractions.ts` → `retractAttraction()` | `requireOwnerOrRole(attraction.owner_id, ['content_moderator','regional_admin','super_admin'])` |
| `verify_restaurant` | `lib/server/listings/restaurants.ts` → `verifyRestaurant()` | `requireRole(['content_moderator','regional_admin','super_admin'])` |
| `retract_restaurant` | `lib/server/listings/restaurants.ts` → `retractRestaurant()` | `requireOwnerOrRole(restaurant.owner_id, ['content_moderator','regional_admin','super_admin'])` |
| `is_admin`, `is_content_admin`, `is_guide`, `is_super_admin` | `lib/auth/permissions.ts` — pure predicates over an already-loaded role (`isAdmin(role)`, `isContentAdmin(role)`, `isGuide(role)`, `isSuperAdmin(role)`) | n/a — these *are* the primitives everything else calls |
| `is_group_member` | `lib/auth/permissions.ts` → `isGroupMember(userId, groupId)` (Prisma lookup against `split_group_members`) | n/a — primitive |
| `is_trip_owner` | `lib/auth/permissions.ts` → `isTripOwner(userId, tripId)` (Prisma lookup against `trips`) | n/a — primitive |
| `lock_profile_role_field` (trigger) | No TS port — **superseded**: `profiles.role` must only ever be written by `updateUserRole()` above, which already enforces `requireRole('super_admin')`. The trigger itself becomes a correctness hazard once writes move to Prisma (see warning above) — tracked as an open question, not resolved by this table alone. | — |
| `lock_attraction_verification_fields` / `lock_restaurant_verification_fields` (triggers) | No TS port — **superseded**: the generic "edit my listing" Server Action must never accept `verification_status`/`verified_by`/`verified_at` in its payload; only `verifyAttraction`/`verifyRestaurant` above may set them, and those already gate on role. Same open-question flag as above. | — |
| `handle_new_user` (trigger on `auth.users`) | No TS port needed — fires inside Supabase Auth's own insert path (guest sign-up, OAuth sign-up), untouched by this migration since Supabase Auth is being kept. **Confirmed via `explorife_schema_export.sql`:** it `INSERT ... ON CONFLICT (id) DO UPDATE` into `public.profiles` on every new `auth.users` row, defaulting `role` to the column default (`'traveler'`) — it never sets `role` itself. Because of this, **`lib/server/profiles.ts` needs no `createProfile()` function at all**: a `profiles` row always already exists by the time any app code runs for a signed-in user, so `updateProfile()`/`updateUserRole()` (both already built) are the only writes that module needs to expose. | — |
| `increment_gems_score`, `increment_journal_score` (triggers) | No TS port needed — don't read `auth.uid()`, fire identically under Prisma-driven writes | — |
| `upsert_gem_from_sheet`, `upsert_tour_from_sheet`, `upsert_curated_collection_from_sheet` | Out of scope (Risk #10) — Apps Script keeps calling these directly over PostgREST; unaffected since that path never goes through Prisma | — |
| `st_estimatedextent` (×3 overloads) | PostGIS-internal, not application logic — leave alone | — |

---

## 4. Third-Party Services

| Service | Purpose | Where used | Migration note |
|---|---|---|---|
| **Supabase** (Postgres + Auth + Storage + Edge Functions) | Backend of record | `lib/main.dart` init; all providers/repositories; `supabase/functions/admin-create-user` | **Kept, per §0.** Postgres is accessed via Prisma (elevated connection, bypasses RLS — authz moved to `lib/auth/permissions.ts`, see §3a). Auth stays Supabase Auth, driven from Next.js via `@supabase/ssr` (cookie-based server/client helpers), including anonymous sessions and `linkIdentity` for guest→real upgrade (Risk #8). Storage buckets `gem-photos`/`trip-covers` are kept as-is (Risk #7). Realtime is deferred to polling/revalidation for now (Risk #9). The one Edge Function in-repo (`admin-create-user`) is superseded by the §3a TypeScript admin functions; the 4 untracked `qa-*-harness` functions are out of scope (Risk #4). |
| **Google OAuth** (via Supabase Auth) | Primary sign-in | `auth_provider.dart`, `oauth_button.dart` | Unchanged — still brokered by Supabase Auth. Next.js side just calls `supabase.auth.signInWithOAuth({ provider: 'google' })` via the `@supabase/ssr` browser client; no new OAuth client credentials needed since Supabase already holds them. |
| **GitHub OAuth** (via Supabase Auth) | Secondary sign-in | `auth_provider.dart` | Same as above, via Supabase Auth's existing GitHub provider config. |
| **Mapbox** | Maps, geocoding, place search, static images, nearby-POI | `lib/core/services/geocoding_service.dart` (Search Geocoding v6), `mapbox_search_service.dart` (Search Box v1), `mapbox_tilequery_service.dart` (Tilequery v4), map screens | Can be kept as-is (Mapbox has a solid JS/web SDK) or swapped — no Supabase dependency, so this migration can carry it over unchanged if desired. |
| **Vercel** | Web hosting | Edge function's invite-redirect default (`https://explorife2.vercel.app`), `deploy.sh` workflow referenced in memory | Natural fit for Next.js too; redirect URLs will need updating to the new app's auth callback route. |

**Confirmed absent** (per repo-wide search): Stripe/PayPal/any payment processor,
Firebase (messaging/crashlytics/analytics), Sentry/PostHog/Mixpanel, any
outbound email service beyond Supabase Auth's built-in invite/magic-link email,
Apple Sign-In.

---

## 5. Environment Variables

Per §0, Supabase stays the infrastructure (Postgres via Prisma, Auth/Storage via
`@supabase/ssr`), so the Supabase client env vars are **kept**, not replaced —
the only genuinely new variables are the two Prisma connection strings. Final
list for Step 2's `.env.example`:

| Variable | Purpose | Tier | Status |
|---|---|---|---|
| `DATABASE_URL` | Prisma's runtime connection — Supabase's **transaction pooler** (PgBouncer, port 6543, `?pgbouncer=true`) connection string. Used by every Server Action/Route Handler. | Secret | **New** |
| `DIRECT_URL` | Prisma's migration connection — Supabase's **session pooler** (same pooler host, port 5432, no `?pgbouncer=true`) connection string, giving `prisma migrate`/`prisma db pull`/`prisma migrate diff` a full non-transaction-pooled session. Deliberately **not** Supabase's literal "direct connection" host (`db.[project-ref].supabase.co`) — that host is IPv6-only on the free plan and unreachable from most networks/CI runners; the session pooler provides the same capability over IPv4. See `nextjs-app/README.md`'s "Environment variables" section. | Secret | **New** |
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase project URL (was `SUPABASE_URL`) | Public | **Kept**, renamed for Next.js's public-env convention |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase anon/public API key (was `SUPABASE_ANON_KEY`) | Public | **Kept**, renamed — still needed by `@supabase/ssr`'s browser client for Auth and Storage calls, even though Prisma (not PostgREST) now serves data reads/writes |
| `SUPABASE_SERVICE_ROLE_KEY` | Service-role key for any server-only Supabase Admin API calls (e.g. the `admin_create_user_profile` flow's `inviteUserByEmail`/`deleteUser` calls ported into `lib/server/admin/users.ts`, per §3a) | Secret, server-only | **Kept** |
| `NEXT_PUBLIC_MAPBOX_TOKEN` | Mapbox API access (was `MAPBOX_TOKEN`) | Public (domain-restricted) | **Kept**, renamed — no Supabase dependency, carries over unchanged |
| `NEXT_PUBLIC_SITE_URL` | Base URL for Supabase Auth OAuth/invite redirects (was `APP_URL`, used for `INVITE_REDIRECT_TO`) | Public | **Kept**, renamed — points `@supabase/ssr`'s redirect handling and the invite-email flow at the new app's own `/auth/callback` route |

No Auth.js vars (`NEXTAUTH_SECRET`, `GOOGLE_CLIENT_ID`/`SECRET`,
`GITHUB_CLIENT_ID`/`SECRET`) and no object-storage provider vars are needed —
both were artifacts of the pre-approval draft's assumption that Auth.js and a
new storage provider would replace Supabase; per §0 that's no longer the
architecture. `.env.example` itself is produced in Step 2.

---

## 6. Risks and Open Questions — Resolved (per approval)

All 11 items below were open questions in the pre-approval draft. Each is now
resolved per the user's explicit decisions; cross-references point to where
the resolution is implemented in this plan.

1. **`hike_tracks` is already broken in production** — `HikeProvider`
   reads/writes columns (`title`, `activity_type`, `distance_km`,
   `duration_seconds`, `elevation_gain_m`, `started_at`) that don't exist on
   the live table (only `name`, `route`, `featured`, `created_at`, `user_id`,
   `id` exist); matches memory note `project_hike_tracks_column_mismatch.md`.
   **Decision: extend the table additively** to add the six missing columns
   matching the Dart model's intent. Additive migration only — no existing
   column renamed or dropped. To be written as a Step 3 migration.
2. **Dead/duplicate tables** — `user_saved_gems` (duplicates `gem_saves`) and
   `trip_groups` / `trip_expenses` / `trip_members` / `trip_settlements`
   (superseded by the `split_*` tables), all 0 rows. **Decision: verified and
   excluded from the Prisma schema, not dropped from the live DB.** Verified
   via an Explore-agent grep across Dart/SQL-migration/TS-function source: zero
   references anywhere except this plan and the read-only
   `explorife_schema_export.sql` snapshot. One caveat found independently:
   `user_saved_gems` still carries a live `on_gem_saved` → `increment_gems_score()`
   trigger (same as `gem_saves`) — dormant since nothing ever inserts into the
   table, but technically a live DB-level reference, not pure dead weight. See
   §3's `user_saved_gems` bullet and the "Legacy/parallel splitting tables"
   subsection for the full writeup.
3. **19 Postgres functions are `SECURITY DEFINER`** and callable by `anon` or
   `authenticated` per the security advisor. **Decision: re-implement every
   one's authorization logic in TypeScript.** Full function → new
   server-action/handler → permission-check mapping is in §3a, including the
   independently-discovered `auth.uid()`/PostgREST-session-GUC finding that
   makes 3 triggers (`lock_profile_role_field`,
   `lock_attraction_verification_fields`, `lock_restaurant_verification_fields`)
   an active correctness hazard under Prisma writes unless superseded by
   equivalent TypeScript checks (flagged in §3a, not yet resolved in code).
4. **4 deployed Edge Functions have no source in the repo**
   (`qa-role-check-harness`, `qa-username-gen-harness`,
   `qa-traveler-session-harness`, `qa-username-taken-check`). **Decision: out
   of scope for this migration.** Left running against the existing Supabase
   project; not ported, not pulled from the dashboard.
5. **`hosting_offers.type` enum values were unresolved.** **Resolved**: an
   `information_schema.columns` lookup filtered on
   `table_name = 'hosting_offers' AND column_name = 'type'` returned
   `udt_name = 'guide_specialty'` — it reuses the existing `guide_specialty`
   enum, not a distinct/unknown type. See §3's Enums subsection; the Prisma
   schema can declare this precisely with no further lookup needed.
6. **`public.spatial_ref_sys` has RLS disabled**, ERROR-level per Supabase's
   linter (plus the related `postgis`-extension-in-`public` WARN, and 3 tables
   — `trip_blueprints`, `trip_members`, `trip_settlements` — with RLS enabled
   but zero policies). **Decision: out of scope for this migration** — the
   user will fix it directly in Supabase, independently of this migration.
   Not touched here.
7. **Storage provider for the new stack** was previously undecided. **Decision:
   keep the existing `gem-photos` and `trip-covers` Supabase Storage buckets**
   — no new provider, no data migration. `@supabase/ssr`'s storage client is
   used from Server Actions/Route Handlers for upload/signed-URL needs. See §0.
8. **Auth provider parity** — Google OAuth, GitHub OAuth, and
   anonymous/guest sessions that upgrade to a real account. **Decision:
   preserve guest mode via Supabase's own anonymous auth + `linkIdentity`**,
   driven through `@supabase/ssr` rather than Auth.js (which was dropped
   entirely per §0 — it has no stock pattern for this and isn't needed since
   Supabase Auth already does it natively).
9. **Realtime features** (`public-saved-gems`, `public-stories` Postgres
   Changes subscriptions) have no direct Next.js/Server-Component equivalent.
   **Decision: use revalidation/polling for now**; real Supabase Realtime
   (via `@supabase/ssr`'s realtime client) is noted as a later enhancement,
   not part of this migration's initial scope.
10. **Google-Sheets → Supabase sync pipeline** (`upsert_gem_from_sheet`,
    `upsert_tour_from_sheet`, `upsert_curated_collection_from_sheet` RPCs)
    feeding `saved_gems`, `tours`, `curated_collections`. **Decision: out of
    scope for now** — not ported to TypeScript (see §3a, listed as "Out of
    scope (Risk #10)"). Constraint: it must keep working against the same
    database, which it will, since the migration doesn't touch these tables'
    shape and the sync writes directly to Postgres independently of the app.
11. **Avatar storage policies with no matching call-site**
    (`avatar_public_read` / `avatar_update_own` on `storage.objects`, no
    avatar-upload code found anywhere). **Decision: no upload feature — ignore
    the avatar storage policies.** Not ported, not investigated further.

---

## 7. Next Steps

**Step 1 (Audit): approved**, with the decisions recorded in §0 and resolved
in §3/§3a/§6 above.

- **Step 2 — Foundation (approved/done)**: Next.js app scaffold (TypeScript
  strict, ESLint, Prettier, Tailwind) in a new directory that doesn't collide
  with Flutter's existing `web/` build-output folder; Tailwind design tokens
  ported from `lib/core/theme/app_theme.dart`; folder structure (`app/`,
  `components/ui`, `components/features`, `lib/` incl. `lib/auth/permissions.ts`,
  `prisma/`); a single shared Prisma client instance (singleton guarded against
  Next.js dev-mode hot-reload duplication); `.env.example` listing the
  variables in §5 (`DATABASE_URL`, `DIRECT_URL`,
  `NEXT_PUBLIC_SUPABASE_URL`/`_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`,
  `NEXT_PUBLIC_MAPBOX_TOKEN`, `NEXT_PUBLIC_SITE_URL`). No storage-provider
  decision is pending (resolved — kept, see Risk #7).
- **Step 3 — Database (done)**: originally planned as `npx prisma db
  pull` against the live Supabase Postgres database (direct connection), but
  the agent has no Postgres password for this project (not exposed by
  Supabase's Management API) and no direct DB connection, so — per explicit
  instruction — `prisma/schema.prisma` was instead **hand-built** from live-DB
  SQL introspection run through the Supabase MCP `execute_sql` tool
  (`information_schema.columns`, `table_constraints`/`key_column_usage`/
  `constraint_column_usage`/`referential_constraints`, `pg_type`/`pg_enum`,
  `pg_indexes`, `pg_trigger`/`pg_proc`), covering every live table, FK,
  unique constraint, enum, and index, batched by domain to avoid
  introspection-query token overflow. Result: all 30 in-scope tables modeled
  (model/field names via `@@map`/`@map`, relations, enums per §3,
  `Unsupported("geography(Point,4326)")` for `gem_guides.location` per §3's
  PostGIS subsection, `multiSchema` with a minimal `User` model mapped to
  `auth.users`); `prisma generate`, `tsc --noEmit`, and `npm run build` all
  pass against it. DB-side behavior Prisma can't express (the PostGIS
  generated column, and three `auth.uid()`-dependent "lock" triggers on
  `profiles.role` and `attractions`/`restaurants` verification fields that
  silently no-op once writes move to Prisma's elevated connection — these
  need to be re-implemented in `lib/auth/permissions.ts`) is documented in
  `prisma/db-notes.sql`. A local/dev-only seed script exists at
  `prisma/seed.ts` (wired via `prisma.config.ts`'s `migrations.seed`, run
  with `npx prisma db seed`), hard-guarded (no bypass env var) against ever
  running except against a `localhost`/`127.0.0.1` `DATABASE_URL` that does
  not reference the live project ref — see "Migration safety rules" below.
  Exclude the Risk #2 dead tables from the schema entirely (already decided,
  not re-litigated at this step — confirmed still present but unmodeled:
  `user_saved_gems`, `trip_groups`, `trip_expenses`, `trip_members`,
  `trip_settlements`, `spatial_ref_sys`).
  **Step 3's three "still open" items — all now closed:**
  1. ~~The `hike_tracks` additive migration (Risk #1) — not yet applied as a
     tracked Prisma migration.~~ **Applied.**
     `prisma/migrations/1_hike_tracks_fields/migration.sql` (plus
     `prisma/migrations/migration_lock.toml`, `provider = "postgresql"`,
     since this was the first migration folder written by hand). Pure
     `ADD COLUMN` on `hike_tracks` — `activity_type`/`title`/`started_at` as
     `NOT NULL` with a default (mirroring the Dart model's required fields
     and `HikeTrack.fromJson`'s fallbacks: `'hiking'`/`'Untitled Hike'`/
     `now()`), `distance_km`/`duration_seconds`/`elevation_gain_m` nullable
     (mirroring `logHike()`'s optional params) — exactly the six columns
     `HikeProvider` already reads/writes but that didn't exist live, matching
     the `HikeTrack` model already hand-built into `schema.prisma`. No
     existing column touched. Generated via schema-to-schema
     `prisma migrate diff --from-schema-datamodel <reverted HikeTrack>
     --to-schema-datamodel prisma/schema.prisma --script` — diffed against a
     temp copy of the schema with just this model's 6 new fields removed, so
     no live DB connection was used or needed to produce it. Deployed by the
     user locally via `prisma migrate deploy` after the baseline below;
     `prisma migrate status` now reports clean/up to date. The Flutter app's
     `HikeProvider.logHike()` (previously failing every insert with Postgres
     42703, undefined_column) should be unblocked — not yet re-verified live,
     worth a manual smoke test next time that flow is touched.
  2. ~~The **baseline migration**, marking the introspected live state as
     already-applied~~ **Done.** Per the explicit decision (option (a)): the
     user ran every step locally, never the agent, and nothing was written to
     `_prisma_migrations` via the Supabase MCP or any other indirect channel.
     Process followed (Prisma 6.19.3): `prisma migrate diff
     --from-schema-datasource prisma/schema.prisma --to-schema-datamodel
     prisma/schema.prisma --script` came back **empty** (confirming
     `prisma/schema.prisma` matches the live DB exactly — the hand-built
     introspection in Step 3 was accurate); `prisma migrate resolve --applied
     0_init` then marked it applied; `prisma migrate status` reported clean.
     `0_init/migration.sql` has since been generated by the agent (via `prisma
     migrate diff --from-empty --to-schema-datamodel` against a `schema.prisma`
     snapshot with `HikeTrack` reverted to its pre-`1_hike_tracks_fields`
     shape, so the two migrations replay correctly in sequence against a fresh
     database) and committed to the repo, alongside `1_hike_tracks_fields` and
     `migration_lock.toml`. Other checkouts now see the real migration history
     instead of a missing/drifted one.
  3. ~~Re-implementing the three `auth.uid()`-dependent trigger protections
     (`profiles.role` lock, `attractions`/`restaurants` verification-field
     locks — see `prisma/db-notes.sql`) in `lib/auth/permissions.ts`, with
     tests, so no Server Action can write those fields without them.~~
     **Done**: `lib/auth/permissions.ts` adds `getUserRole()`,
     `PROFILE_ROLE_CHANGE_ROLES`/`VERIFICATION_MODERATOR_ROLES`, the pure
     predicates `canChangeProfileRole()`/`canSetListingVerification()`, and
     the asserting guards `assertCanChangeProfileRole()`/
     `assertCanVerifyAttraction()`/`assertCanVerifyRestaurant()` (built on a
     new generic `requireRole()`), each mirroring one live trigger's
     authorization condition exactly (role lists cross-checked against
     `prisma/db-notes.sql` §2's trigger SQL). Unit tests in
     `lib/auth/permissions.test.ts` (21 tests, `vitest`, Supabase/Prisma
     mocked) cover the pure predicates against every `Role` plus `null`, and
     the assert-guards' Auth/Forbidden/success paths. `npx vitest run`,
     `npx tsc --noEmit`, and `npx eslint` all pass clean. Per the module's
     own doc comment, this stops *unauthorized* writes from ever reaching
     Postgres (clean 403 instead of a silent trigger-revert) but does not by
     itself make *authorized* writes stick — the live triggers still revert
     those until they're altered/dropped on the live DB, which stays the
     separate, approval-gated Risk #3 item. Not yet wired into any Server
     Action (`lib/server/` is still just the placeholder README) — that
     lands with the actual `updateUserRole()`/`verifyAttraction()`/
     `verifyRestaurant()` ports in Step 3a/Step 4. This item was done ahead
     of item 1 (`hike_tracks` migration) and item 2 (baseline), both still
     pending, since it's pure application code with no live-DB write.

### Migration safety rules

These apply from Step 3 onward and are also documented in `README.md`:

- **Never run `prisma migrate dev` or `prisma migrate reset` against the
  live Supabase project.** Both can drop/recreate objects to reconcile
  drift. The only live-safe path for schema changes is: `prisma migrate
  diff` → human review of the generated SQL → `prisma migrate deploy`.
- **Never write to `_prisma_migrations` via the Supabase MCP** (or any
  other indirect channel) to fake a baseline. Baselining is done by the
  user, locally, via `prisma migrate resolve --applied`, per the Step 3
  "Still open" item 2 process above.
- **Local iteration happens against a Supabase-CLI-provisioned local
  Postgres** (`supabase start`), which includes a real local `auth` schema
  — `prisma migrate dev` is safe there (never against the live project).
  Setup steps and a separate local `DATABASE_URL` are documented in
  `README.md`'s "Local development database" section.
- **The seed script (`prisma/seed.ts`) hard-refuses to run** unless
  `DATABASE_URL` is a `localhost`/`127.0.0.1` host and does not contain the
  production project ref (`yshgjzmyapdepkapodno`). There is no override/
  bypass env var — this is intentional so it can't be run against
  production by muscle memory.
- **Step 4 — Shared layout**: app shell, profile header (including the new
  nested `/profile/*` routes per §1's routing-change subsection), trip header
  + switcher, per the original instructions' "Step 4" scope.

Each step stops for review before proceeding to the next, per the user's
explicit instruction after Step 1's approval ("Stop again after Step 2 for
review").

**This plan is awaiting your explicit approval before any of the above starts.**
