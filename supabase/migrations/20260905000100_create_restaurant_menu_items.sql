-- Menu Highlights storage decision (see
-- docs/audits/restaurant-business-profile-2026-09-05.md for the full
-- trade-off write-up): a LINKED TABLE, one row per dish, rather than a
-- JSON/array column on restaurants itself. Chosen because (a) this app
-- already models every other multi-item business/curated concept as a real
-- table (saved_gems, tours, attractions — never a JSON blob column), (b)
-- per-dish photos are cleanly one column here vs. needing a nested
-- array-of-objects shape in JSON, and (c) it doesn't foreclose a future
-- "search by dish" feature — a JSON column would need a full rewrite to
-- support that; a real table with a restaurant_id FK already does. The
-- trade-off: this ships slightly slower than a JSON column would have
-- (a second table, second repository surface, second RLS set) — judged
-- worth it given (a)-(c) above.
create table if not exists public.restaurant_menu_items (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants (id) on delete cascade,

  dish_name text not null,
  price_amount integer not null check (price_amount >= 0),
  currency text not null default 'VND',
  photo_url text,

  -- Owner-controlled display order (menu items don't have a natural sort
  -- key otherwise) — lets an owner put their signature dishes first without
  -- renaming them to force alphabetical order.
  display_order integer not null default 0,

  created_at timestamptz not null default now()
);

alter table public.restaurant_menu_items enable row level security;

-- Visibility mirrors the parent restaurant's own read policies exactly —
-- a menu item is only ever "public" when its restaurant is (verified,
-- not retracted); an owner sees their own restaurant's menu regardless of
-- status; an admin sees everything. There is no independent
-- verification_status on menu items themselves — one status covers the
-- whole listing, same as Attraction's certification_urls is covered by
-- the single attractions.verification_status rather than a second,
-- per-field verification concept.
create policy "public can view menu items for verified restaurants"
  on public.restaurant_menu_items for select
  using (
    exists (
      select 1 from public.restaurants
      where restaurants.id = restaurant_menu_items.restaurant_id
        and restaurants.verification_status = 'verified'
        and restaurants.deleted_at is null
    )
  );

create policy "admins can view all restaurant menu items"
  on public.restaurant_menu_items for select
  using (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid()
        and profiles.role in ('content_moderator', 'regional_admin', 'super_admin')
    )
  );

-- Only the restaurant's own owner manages its menu — admins verify/
-- retract the listing as a whole, they don't edit its menu content.
create policy "owners can manage own restaurant menu items"
  on public.restaurant_menu_items for all
  using (
    exists (
      select 1 from public.restaurants
      where restaurants.id = restaurant_menu_items.restaurant_id
        and restaurants.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.restaurants
      where restaurants.id = restaurant_menu_items.restaurant_id
        and restaurants.owner_id = auth.uid()
    )
  );
