-- Structured place data for trips.location, resolved from the new Mapbox
-- autocomplete on the trip-setup wizard's "Where to?" field. Nullable: a
-- free-typed location (no suggestion selected) has no coordinates, same as
-- every trip created before this feature existed — location itself stays the
-- display string, this is purely additive.
alter table public.trips
  add column if not exists location_lat double precision,
  add column if not exists location_lng double precision;
