-- Real start time + freeform notes for itinerary stops. Additive; existing
-- rows are unaffected. start_time is a plain time-of-day (no timezone
-- concerns — it's display/planning metadata, not an event with a timezone),
-- notes is a freeform per-stop text field for the My Trip inline editor.

alter table public.trip_stops
  add column if not exists start_time time;

alter table public.trip_stops
  add column if not exists notes text;
