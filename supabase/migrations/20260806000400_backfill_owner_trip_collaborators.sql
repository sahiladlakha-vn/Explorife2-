-- Gives every trip's owner a real trip_collaborators row, so "assignee" /
-- "document owner" pickers (which FK to trip_collaborators.id) can reference
-- the owner the same way they reference any other traveler. Previously the
-- owner was synthesized client-side as a fake row with `id = owner_id` (a
-- user id, not a trip_collaborators id) — that meant the owner could never
-- actually be picked as a packing-item assignee or a document owner, since
-- there was no real row to point the FK at.
--
-- Purely additive for RLS: every existing policy already grants the owner
-- full access via `t.owner_id = auth.uid()`, independent of any
-- trip_collaborators row. Adding one with permission='edit' doesn't change
-- what the owner can do — it only makes them referenceable.
insert into public.trip_collaborators (trip_id, user_id, permission, status)
select t.id, t.owner_id, 'edit', 'confirmed'
from public.trips t
where not exists (
  select 1 from public.trip_collaborators c
   where c.trip_id = t.id and c.user_id = t.owner_id
)
on conflict (trip_id, user_id) do nothing;
