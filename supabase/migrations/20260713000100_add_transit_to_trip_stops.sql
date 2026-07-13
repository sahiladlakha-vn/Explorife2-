-- Transit-in fields for itinerary stops. Semantics: how you get FROM the
-- previous stop TO this one (mode, line/route label, duration, cost). All
-- nullable — a stop with no transit leg (e.g. the day's first stop, or a
-- walk-up) simply leaves them null. Additive; existing rows are unaffected.
--
-- Cost follows the house money convention (*_vnd bigint: budget_vnd, price_vnd,
-- planned_vnd) rather than a bare numeric, so transit cost stays in the same
-- VND world as the rest of trip budget/pace math.

alter table public.trip_stops
  add column if not exists transit_mode text;

alter table public.trip_stops
  add column if not exists transit_line text;

alter table public.trip_stops
  add column if not exists transit_duration_min int;

alter table public.trip_stops
  add column if not exists transit_cost_vnd bigint;
