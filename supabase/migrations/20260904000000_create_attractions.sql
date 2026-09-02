-- Attraction — the first of 8 business profile types (Hotel, Tour Operator,
-- Guide, Transportation, Restaurant, Attraction, Wellness, Retail), built
-- one at a time per product's sequencing. See
-- docs/audits/attraction-business-profile-2026-09-04.md for the full
-- written decision this migration implements.
--
-- GEM RELATIONSHIP (resolved, not left ambiguous): Attraction is its own
-- record, OPTIONALLY linked to an existing curated Gem via `gem_id` when
-- the app's client-side name+proximity check (see
-- lib/screens/attractions/attraction_form_screen.dart) finds a plausible
-- match at creation time, confirmed by an Admin during verification. A
-- linked Gem's own curated content (description/photos) is NEVER replaced
-- or merged — Gem Detail keeps showing exactly what it shows today, with
-- the Attraction's business info (entry fee, hours, verified badge)
-- surfacing as an ADDITIONAL section. An Attraction with gem_id null is a
-- genuinely new place with no prior curated entry.
--
-- CATEGORY (resolved): reuses Gem's existing 10-category taxonomy exactly
-- (hiking/camping/viewpoint/food/temple/cave/coastal/nature/heritage/
-- landmark) rather than the source schema's own 5-value list (Museum/Park/
-- Historical Site/Adventure Activity/Theme Park) — those don't map 1:1,
-- but keeping ONE taxonomy across Gem and Attraction (rather than two
-- different category systems for what can be the exact same place once
-- linked) was judged more important than schema literalism. Museum/
-- Historical Site -> heritage, Park -> nature, Theme Park/Adventure
-- Activity -> closest fit (landmark/hiking) at the app layer — see
-- Attraction.category in lib/models/attraction.dart.
create table if not exists public.attractions (
  id uuid primary key default gen_random_uuid(),

  -- The Business-Owner-role account this listing belongs to. Required for
  -- the permissions matrix's "own only" rows (Create/edit own business
  -- profile, Manage own bookings/calendar) to mean anything — not in the
  -- source schema explicitly, but there is no functioning ownership model
  -- without it.
  owner_id uuid not null references auth.users (id) on delete cascade,

  -- Nullable — see the GEM RELATIONSHIP note above. SET NULL (not
  -- CASCADE): deleting the curated Gem someday must not silently delete a
  -- real business's listing.
  gem_id uuid references public.saved_gems (id) on delete set null,

  name text not null,
  category text not null
    check (category in (
      'hiking', 'camping', 'viewpoint', 'food', 'temple', 'cave', 'coastal',
      'nature', 'heritage', 'landmark'
    )),
  gallery text[] not null default '{}',

  address text not null,
  latitude double precision not null,
  longitude double precision not null,
  opening_hours text not null,

  -- "Free or paid + amount" from the source schema — mirrors Tour's own
  -- money contract (amount is genuinely absent for 'free', not zero-as-a-
  -- stand-in-for-unknown).
  entry_fee_type text not null check (entry_fee_type in ('free', 'paid')),
  entry_fee_amount integer,
  currency text not null default 'VND',
  constraint entry_fee_amount_matches_type check (
    (entry_fee_type = 'free' and entry_fee_amount is null)
    or (entry_fee_type = 'paid' and entry_fee_amount is not null and entry_fee_amount >= 0)
  ),

  description text not null,
  -- File-upload UI for this is deliberately NOT built this phase (see the
  -- doc) — the column exists so an admin can populate it directly, same
  -- "field exists, no authoring UI yet" convention this app already uses
  -- elsewhere (e.g. curated_collections.dart before it has a real CMS).
  certification_urls text[] not null default '{}',
  recommended_duration text,

  verification_status text not null default 'pending'
    check (verification_status in ('pending', 'verified', 'rejected')),
  verified_by uuid references auth.users (id),
  verified_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.attractions enable row level security;

-- Public read is scoped to VERIFIED listings only — an unverified/rejected
-- business claim shouldn't be discoverable by travellers just because a
-- row exists. Owners and admins get their own broader read policies below.
create policy "public can view verified attractions"
  on public.attractions for select
  using (verification_status = 'verified');

create policy "owners can view own attractions"
  on public.attractions for select
  using (auth.uid() = owner_id);

create policy "admins can view all attractions"
  on public.attractions for select
  using (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid()
        and profiles.role in ('content_moderator', 'regional_admin', 'super_admin')
    )
  );

-- "Create/edit own business profile" is Business-Owner-only in the
-- permissions matrix (Guide gets the same row, but Guide is a distinct
-- future profile type with its own listing, not Attractions) — enforced
-- here, not just at the app layer.
create policy "business owners can insert own attractions"
  on public.attractions for insert
  with check (
    auth.uid() = owner_id
    and exists (
      select 1 from public.profiles
      where profiles.id = auth.uid() and profiles.role = 'business_owner'
    )
  );

create policy "owners can update own attractions"
  on public.attractions for update
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

create policy "admins can update any attraction"
  on public.attractions for update
  using (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid()
        and profiles.role in ('content_moderator', 'regional_admin', 'super_admin')
    )
  );

-- Owner-editable columns stop at verification_status/verified_by/
-- verified_at — an owner's own UPDATE policy above would otherwise let
-- them set verification_status = 'verified' on their own listing directly.
-- Rather than relying on client-side discipline (which field selection a
-- form happens to expose), this is enforced with a trigger that silently
-- reverts those 3 columns to their prior value whenever the acting user
-- isn't an admin-tier account — real enforcement regardless of what a
-- client sends.
create or replace function public.lock_attraction_verification_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.profiles
    where profiles.id = auth.uid()
      and profiles.role in ('content_moderator', 'regional_admin', 'super_admin')
  ) then
    new.verification_status := old.verification_status;
    new.verified_by := old.verified_by;
    new.verified_at := old.verified_at;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger attractions_lock_verification_fields
  before update on public.attractions
  for each row
  execute function public.lock_attraction_verification_fields();

-- The sanctioned path for "Approve/reject business listings" (permissions
-- matrix row) — updates the listing AND writes a real admin_action_log
-- entry in one transaction, giving that table (built in the Role
-- foundation phase with no caller yet) its first real caller. Raises if
-- the caller isn't admin-tier, same check as the trigger above but
-- fail-loud here since this IS the intended write path (the trigger is
-- the backstop against someone bypassing this RPC with a raw update).
create or replace function public.verify_attraction(
  p_attraction_id uuid,
  p_approve boolean
)
returns public.attractions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.user_role;
  v_row public.attractions;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is null or v_role not in ('content_moderator', 'regional_admin', 'super_admin') then
    raise exception 'only Content Moderator, Regional Admin, or Super Admin can verify a business listing';
  end if;

  update public.attractions
  set verification_status = case when p_approve then 'verified' else 'rejected' end,
      verified_by = auth.uid(),
      verified_at = now()
  where id = p_attraction_id
  returning * into v_row;

  if v_row.id is null then
    raise exception 'attraction not found: %', p_attraction_id;
  end if;

  insert into public.admin_action_log (actor_id, action_type, target_profile_id)
  values (
    auth.uid(),
    case when p_approve then 'approve_listing' else 'reject_listing' end,
    p_attraction_id
  );

  return v_row;
end;
$$;

grant execute on function public.verify_attraction(uuid, boolean) to authenticated;
