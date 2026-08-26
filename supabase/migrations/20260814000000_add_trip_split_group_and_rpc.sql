-- Links a trip to exactly one "shadow" split group, auto-provisioned the
-- first time anyone logs an expense against that trip from the Overview
-- tab's new "+ Add Expense" button — the user never sees "groups" at all.
-- Nullable: standalone split groups (the existing /splits feature, unrelated
-- to any trip) keep trip_id null. Unique so a trip can never end up with two
-- shadow groups.
alter table public.split_groups
  add column if not exists trip_id uuid unique references public.trips(id) on delete cascade;

-- Atomic get-or-create, callable by any authenticated user regardless of
-- whether they can already SELECT the group row under RLS (a second
-- traveler adding an expense to an existing shadow group they're not yet a
-- member of couldn't otherwise even see it exists, and would try to insert
-- a duplicate — hitting the unique constraint above). security definer lets
-- this bypass that read gap safely; the unique index makes the insert
-- itself race-safe if two travelers tap "Add Expense" for the first time
-- at the same moment.
--
-- Also ensures the CALLER is a split_group_members row on the returned
-- group, whether they created it or it already existed — required by
-- split_expenses' own insert policy (is_group_member(group_id)), so the
-- caller can actually log an expense against what this returns.
create or replace function public.get_or_create_trip_split_group(p_trip_id uuid, p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group_id uuid;
begin
  insert into public.split_groups (trip_id, name, created_by)
  values (p_trip_id, p_name, auth.uid())
  on conflict (trip_id) do nothing;

  select id into v_group_id from public.split_groups where trip_id = p_trip_id;

  insert into public.split_group_members (group_id, user_id)
  select v_group_id, auth.uid()
  where not exists (
    select 1 from public.split_group_members
    where group_id = v_group_id and user_id = auth.uid()
  );

  return v_group_id;
end;
$$;

revoke all on function public.get_or_create_trip_split_group(uuid, text) from public;
grant execute on function public.get_or_create_trip_split_group(uuid, text) to authenticated;
