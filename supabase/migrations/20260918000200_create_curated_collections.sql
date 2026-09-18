-- Home's "EXPLORE IDEAS" rail (lib/core/constants/curated_collections.dart)
-- was a hardcoded static Dart list with no CMS/admin screen and no
-- Supabase backing at all — this table replaces that, following the exact
-- same "curated, publicly-readable, no owner column, no client write
-- policy" shape as public.tours (see 20260901000000_create_tours.sql's own
-- doc comment for the full reasoning).
--
-- One row = one CuratedCollection: either a destination-scoped card (a
-- city name, resolved to coordinates client-side on tap) or a
-- category-scoped card (one of Gem.categories, or the literal 'all').
create table if not exists public.curated_collections (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  subtitle text,
  cover_image_url text,
  -- true = scope_value is a city name (destination card); false =
  -- scope_value is a Gem category or 'all' (category card). Mirrors
  -- CollectionScope.isDestination exactly.
  is_destination boolean not null default true,
  scope_value text not null,
  -- Curator-assigned, NOT an aggregated review score — see
  -- CuratedCollection.rating's own doc comment in curated_collections.dart
  -- for why this app has no real review backend to source one from.
  -- Destination-scope only by UI convention, not DB-enforced (same as the
  -- Dart model never enforcing it either — a category row just leaves it
  -- null and the card omits the badge).
  rating numeric,
  best_time_to_visit text,
  -- Row insertion order isn't guaranteed by Postgres — the rail's
  -- left-to-right order needs an explicit column, unlike the old Dart
  -- const list where array order WAS the display order.
  sort_order integer not null default 0,
  -- Same convention as saved_gems.source (20260905000300) — lets the app
  -- (once it reads from this table) distinguish hand-authored/migrated
  -- rows from ones a future sheet sync writes, if that distinction is ever
  -- needed; defaults to 'app' for the seed migration that follows this one.
  source text not null default 'app' check (source in ('app', 'sheet_sync')),
  created_at timestamptz not null default now()
);

alter table public.curated_collections enable row level security;

create policy "curated_collections are publicly readable"
  on public.curated_collections
  for select
  using (true);
