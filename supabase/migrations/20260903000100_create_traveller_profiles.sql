-- Traveller profile — the extended, private data that doesn't belong on
-- the lightweight, publicly-readable `profiles` table (display identity
-- shared across trips/collaborators). One row per traveller account,
-- 1:1 with auth.users via user_id.
--
-- Fields deliberately OMITTED from the source schema, per this phase's
-- explicit scope:
--   - loyalty_points: no loyalty program is planned anywhere in this app
--     today — building a dead counter field would be exactly the "build
--     it only if actually planned" case this phase was told to skip.
--   - payment_methods: no payment provider has been chosen yet (this app
--     has no real booking/payment backend — see Tour's own doc comment).
--     Tokenizing "raw card data" with no real provider behind it would be
--     a fake-looking field, not a real one.
--   - bookings_history / reviews_written: NOT stored columns — see the
--     app-side TravellerProfileRepository. Bookings History is a live
--     query against the real trip_bookings table (joined through trips
--     for owner_id); Reviews Written has nothing to query yet, since this
--     app has no reviews/ratings feature anywhere (Gems have none, Tours
--     explicitly deferred them) — it returns an honest empty list, not a
--     fabricated one.
--   - wishlist: reuses the existing gem_saves save/favorite mechanism
--     (GemProvider.toggleSave) rather than a second, parallel saved-items
--     system — see TravellerProfileRepository's doc comment.
create table if not exists public.traveller_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,

  date_of_birth date,
  gender text check (gender is null or gender in ('male', 'female', 'other', 'prefer_not_to_say')),
  nationality text,

  phone text,
  -- Reflects the real, currently-supported OAuth providers only (Google,
  -- GitHub) — NOT the source schema's Email/Google/Facebook/Apple list,
  -- since this app has no email/password flow and no Facebook/Apple sign-in
  -- today. Set from auth.users' own app_metadata.provider at profile
  -- creation, never hand-typed.
  login_method text check (login_method is null or login_method in ('google', 'github')),
  preferred_language text,
  -- Distinct value set from admin_profiles.account_status (Active/Suspended/
  -- Deactivated here vs. Active/Suspended/Inactive there) — matches the
  -- source schema exactly, which defines each independently.
  account_status text not null default 'active'
    check (account_status in ('active', 'suspended', 'deactivated')),

  interests text[] not null default '{}',
  travel_style text check (travel_style is null or travel_style in ('solo', 'couple', 'family', 'group', 'business')),
  budget_range text check (budget_range is null or budget_range in ('$', '$$', '$$$', '$$$$')),
  home_location text,

  verification_status text not null default 'unverified'
    check (verification_status in ('unverified', 'email_verified', 'id_verified')),
  emergency_contact text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.traveller_profiles enable row level security;

-- Private extended data (DOB, emergency contact, etc.) — unlike `profiles`,
-- this is NOT publicly readable. Only the account owner (and, per the
-- permissions matrix, a Super Admin managing accounts — added once an
-- admin UI actually needs it, not speculatively here).
create policy "travellers can view own profile"
  on public.traveller_profiles for select
  using (auth.uid() = user_id);

create policy "travellers can insert own profile"
  on public.traveller_profiles for insert
  with check (auth.uid() = user_id);

create policy "travellers can update own profile"
  on public.traveller_profiles for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
