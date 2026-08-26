-- Freeform "what is this trip about" text, captured by the setup wizard's
-- new Description field. Nullable — every trip created before this feature
-- existed (and any trip where the user leaves it blank) has none.
alter table public.trips
  add column if not exists description text;
