-- Makes price_vnd nullable so "not yet priced" (TBD) becomes representable,
-- distinct from a genuinely free (₫0) stop — the same MONEY CONTRACT
-- already established for trip_bookings.amount_vnd (see that table's own
-- doc comment). Previously `not null default 0` meant every unpriced stop
-- silently read as "free."
--
-- Existing rows are NOT backfilled to null: a historical price_vnd = 0 could
-- honestly mean either "confirmed free" or "never priced," and there's no
-- way to tell them apart retroactively. Leaving existing rows at their
-- current value (0) is the least-surprising choice — only stops created
-- after this migration (and the matching app-side default change) start
-- life as null/TBD.
alter table public.trip_stops
  alter column price_vnd drop not null;

alter table public.trip_stops
  alter column price_vnd drop default;
