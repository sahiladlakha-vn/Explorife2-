-- Explicit stop -> booking link, for the Itinerary's "Booked" chip and cost
-- fallback (price_vnd ?? booking.amount_vnd). Deliberately an explicit FK
-- rather than a derived gem+date match: a trip can have the same gem booked
-- twice, or a booking with no stop link at all (trip_bookings.stop_id is a
-- separate, unrelated column — the two aren't reconciled against each
-- other; this is the one write path for "is this stop booked").
--
-- SET NULL (not CASCADE), matching every other optional link in this
-- schema (trip_bookings.stop_id, trip_documents.owner_collaborator_id,
-- trip_packing_items.assignee_collaborator_id): deleting the booking must
-- not delete the stop, just unlink it.
alter table public.trip_stops
  add column if not exists booking_id uuid references public.trip_bookings(id) on delete set null;

create index if not exists trip_stops_booking_id_idx
  on public.trip_stops (booking_id);
