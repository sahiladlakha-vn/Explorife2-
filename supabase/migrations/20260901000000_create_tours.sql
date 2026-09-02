-- Trail/Tour content type — deliberately separate from saved_gems. Bookable,
-- priced experiences (day tours, multi-stop trips), not the same thing as a
-- Gem (a free, crowdsourced hidden spot). See lib/models/tour.dart's doc
-- comment for the full reasoning, especially why there's no
-- rating/review columns here: no real booking/payment backend exists yet
-- to legitimately source them from.
--
-- Publicly readable, no client-side write policy — there's no creation UI
-- for this content yet, so rows are added directly in Supabase (same entry
-- path as this app's other curated-but-not-yet-authorable content, e.g.
-- curated_collections.dart before it has a real CMS).
create table if not exists public.tours (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  photos text[] not null default '{}',
  -- One of Gem.categories (lib/models/gem.dart) — reuses the existing
  -- 10-category taxonomy rather than a second parallel one (confirmed with
  -- product). Not FK-constrained to a categories table (Gem's own category
  -- column isn't either) — validated at the app layer, same convention.
  category text,
  price_from integer not null default 0,
  currency text not null default 'VND',
  duration_label text,
  cancellation_policy text,
  pickup_included boolean not null default false,
  pickup_detail text,
  guide_languages text[] not null default '{}',
  includes text[] not null default '{}',
  -- Array of {title, description} objects — see TourItineraryStep.fromJson.
  itinerary jsonb not null default '[]',
  highlights text[] not null default '{}',
  full_description text,
  -- Drives the "Top pick" badge. Explicitly set by whoever curates this
  -- content — never derived from a rating/popularity score (there isn't
  -- one; see the no-reviews decision above).
  is_curated boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.tours enable row level security;

create policy "tours are publicly readable"
  on public.tours
  for select
  using (true);
