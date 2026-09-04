-- Restaurant — the second of 8 business profile types. Attraction (see
-- docs/audits/attraction-business-profile-2026-09-04.md) set the pattern:
-- Gem-linking via gem_id, verification via RLS + a field-lock trigger + a
-- verify_* RPC, soft-delete via deleted_at + a retract_* RPC. This
-- migration reuses that pattern exactly — see
-- docs/audits/restaurant-business-profile-2026-09-05.md for what's
-- actually different about Restaurant (Menu Highlights storage, Reservation
-- Option being informational-only, no rating/reviews field) and why.
--
-- CATEGORY: unlike Attraction (genuine 5-vs-10 taxonomy mismatch), every
-- Restaurant is simply category = 'food' — an exact match with Gem's
-- existing taxonomy already, no mapping decision needed. Cuisine Type is a
-- separate multi-select tag (cuisine_type below), not the category.
--
-- RATING/REVIEWS: deliberately NOT a column here. This app has no
-- reviews/ratings mechanism anywhere (Gems have none, Tour explicitly
-- deferred it, Attraction explicitly left it out) — adding a fabricated
-- rating field with nothing to compute it from would be worse than no
-- field at all. Revisit if/when a real review system is ever built, for
-- every listing type at once, not per-business-type.
create table if not exists public.restaurants (
  id uuid primary key default gen_random_uuid(),

  owner_id uuid not null references auth.users (id) on delete cascade,

  -- Nullable — same Gem-linking mechanism as Attraction (see
  -- restaurant_form_screen.dart's use of findLikelyGemMatch). SET NULL, not
  -- CASCADE: deleting the curated Gem must not silently delete a real
  -- restaurant's listing.
  gem_id uuid references public.saved_gems (id) on delete set null,

  name text not null,
  -- Fixed, not user-selectable — see the CATEGORY note above.
  category text not null default 'food' check (category = 'food'),
  cuisine_type text[] not null default '{}',
  price_range text not null
    check (price_range in ('$', '$$', '$$$', '$$$$')),
  gallery text[] not null default '{}',

  address text not null,
  latitude double precision not null,
  longitude double precision not null,
  phone text not null,
  opening_hours text not null,

  dietary_options text[] not null default '{}',
  -- Informational only — "Reservations accepted" / "Walk-ins only" on the
  -- detail screen and the Gem Detail card, never a booking action. Same
  -- reasoning Tour's "Check availability" was deferred for: no real
  -- reservation backend exists to book against, so a button implying one
  -- would be a dead end. Revisit if a real reservation flow is ever built.
  reservation_option boolean not null default false,

  -- Text/URL field, no upload UI this phase — same "field exists, no
  -- authoring UI yet" convention as Attraction's certification_urls (an
  -- admin can populate it directly). Singular, not an array: the source
  -- schema describes ONE business license per restaurant, unlike
  -- Attraction's certification_urls which genuinely can be plural.
  business_license_url text,

  verification_status text not null default 'pending'
    check (verification_status in ('pending', 'verified', 'rejected')),
  verified_by uuid references auth.users (id),
  verified_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.restaurants enable row level security;

-- Excludes deleted_at from the start (added retroactively for Attraction
-- after a review found the gap) — see the deleted_at column further down
-- and docs/audits/restaurant-business-profile-2026-09-05.md's "proactive
-- audit" note: this phase applies the Attraction deleted_at fix from day
-- one instead of waiting for a second pass.
alter table public.restaurants add column deleted_at timestamptz;

create policy "public can view verified restaurants"
  on public.restaurants for select
  using (verification_status = 'verified' and deleted_at is null);

create policy "owners can view own restaurants"
  on public.restaurants for select
  using (auth.uid() = owner_id);

create policy "admins can view all restaurants"
  on public.restaurants for select
  using (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid()
        and profiles.role in ('content_moderator', 'regional_admin', 'super_admin')
    )
  );

create policy "business owners can insert own restaurants"
  on public.restaurants for insert
  with check (
    auth.uid() = owner_id
    and exists (
      select 1 from public.profiles
      where profiles.id = auth.uid() and profiles.role = 'business_owner'
    )
  );

create policy "owners can update own restaurants"
  on public.restaurants for update
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

create policy "admins can update any restaurant"
  on public.restaurants for update
  using (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid()
        and profiles.role in ('content_moderator', 'regional_admin', 'super_admin')
    )
  );

-- Same shape as attractions_lock_verification_fields — an owner's own
-- UPDATE policy above would otherwise let them set
-- verification_status = 'verified' on their own listing directly.
create or replace function public.lock_restaurant_verification_fields()
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

create trigger restaurants_lock_verification_fields
  before update on public.restaurants
  for each row
  execute function public.lock_restaurant_verification_fields();

-- Same shape as verify_attraction — reuses admin_action_log's existing
-- approve_listing/reject_listing action types (already generic across
-- business types, no new type needed).
create or replace function public.verify_restaurant(
  p_restaurant_id uuid,
  p_approve boolean
)
returns public.restaurants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.user_role;
  v_row public.restaurants;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is null or v_role not in ('content_moderator', 'regional_admin', 'super_admin') then
    raise exception 'only Content Moderator, Regional Admin, or Super Admin can verify a business listing';
  end if;

  update public.restaurants
  set verification_status = case when p_approve then 'verified' else 'rejected' end,
      verified_by = auth.uid(),
      verified_at = now()
  where id = p_restaurant_id
  returning * into v_row;

  if v_row.id is null then
    raise exception 'restaurant not found: %', p_restaurant_id;
  end if;

  insert into public.admin_action_log (actor_id, action_type, target_profile_id)
  values (
    auth.uid(),
    case when p_approve then 'approve_listing' else 'reject_listing' end,
    p_restaurant_id
  );

  return v_row;
end;
$$;

grant execute on function public.verify_restaurant(uuid, boolean) to authenticated;

-- Same shape as retract_attraction — reuses the existing retract_listing
-- action type. Only the admin-driven path logs to admin_action_log; an
-- owner retracting their own listing does not (see retract_attraction's
-- own comment for why — the same reasoning applies unchanged).
create or replace function public.retract_restaurant(p_restaurant_id uuid)
returns public.restaurants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.user_role;
  v_is_admin boolean;
  v_row public.restaurants;
begin
  select role into v_role from public.profiles where id = auth.uid();
  v_is_admin := v_role in ('content_moderator', 'regional_admin', 'super_admin');

  update public.restaurants
  set deleted_at = now()
  where id = p_restaurant_id
    and deleted_at is null
    and (owner_id = auth.uid() or v_is_admin)
  returning * into v_row;

  if v_row.id is null then
    raise exception 'restaurant not found, already retracted, or not permitted: %', p_restaurant_id;
  end if;

  if v_is_admin then
    insert into public.admin_action_log (actor_id, action_type, target_profile_id)
    values (auth.uid(), 'retract_listing', p_restaurant_id);
  end if;

  return v_row;
end;
$$;

grant execute on function public.retract_restaurant(uuid) to authenticated;
