-- Resolves a gap found in code review: `public.attractions` had RLS
-- enabled with no DELETE policy at all — neither an owner nor an
-- admin-tier account could remove a listing through the normal client
-- API. Confirmed NOT intentional; there's a real product need (a business
-- closes down and its owner wants to stop advertising it; an admin needs
-- to pull a listing that later turns out to violate policy even after
-- verification).
--
-- Resolved as SOFT delete, not a hard DELETE policy — matching this app's
-- own established convention (every account-status field in this schema —
-- traveller_profiles.account_status, admin_profiles.account_status — is a
-- status flag, never a row deletion) and keeping a full history for
-- admin_action_log to log against, the same way approve/reject already do.
-- A hard-deleted row can't be referenced by a later log entry; a
-- soft-deleted one still can.
alter table public.attractions add column deleted_at timestamptz;

-- The public feed excludes soft-deleted listings — a retracted business
-- shouldn't keep showing up just because it was verified before being
-- pulled. Owners and admins keep seeing their own/all listings regardless
-- (including retracted ones — e.g. for an owner's "past listings" view),
-- since only THIS policy scopes what a stranger can see.
drop policy "public can view verified attractions" on public.attractions;
create policy "public can view verified attractions"
  on public.attractions for select
  using (verification_status = 'verified' and deleted_at is null);

-- New loggable action type for the admin-driven retraction path (see
-- retract_attraction below) — owner self-retraction does NOT get logged
-- here (see that function's own comment for why: admin_action_log is for
-- admin oversight, not a general audit of every user action).
alter table public.admin_action_log drop constraint admin_action_log_action_type_check;
alter table public.admin_action_log add constraint admin_action_log_action_type_check
  check (action_type in (
    'approve_listing', 'reject_listing',
    'verify_license',
    'moderate_content',
    'suspend_account', 'ban_account',
    'manage_payment',
    'assign_role',
    'retract_listing'
  ));

-- The sanctioned retraction path for EITHER the listing's own owner (any
-- time, any verification status — a closed business shouldn't need an
-- admin's permission to stop advertising itself) OR an admin-tier account
-- acting on someone else's listing (moderation power). Only the latter
-- gets written to admin_action_log: an owner retracting their own listing
-- isn't an "admin action" in the sense that table exists to track, and an
-- account can't hold both a business_owner and an admin-tier role at once
-- (Role foundation's "every account has exactly one Role" rule), so the
-- two paths never overlap for the same caller.
create or replace function public.retract_attraction(p_attraction_id uuid)
returns public.attractions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.user_role;
  v_is_admin boolean;
  v_row public.attractions;
begin
  select role into v_role from public.profiles where id = auth.uid();
  v_is_admin := v_role in ('content_moderator', 'regional_admin', 'super_admin');

  update public.attractions
  set deleted_at = now()
  where id = p_attraction_id
    and deleted_at is null
    and (owner_id = auth.uid() or v_is_admin)
  returning * into v_row;

  if v_row.id is null then
    raise exception 'attraction not found, already retracted, or not permitted: %', p_attraction_id;
  end if;

  if v_is_admin then
    insert into public.admin_action_log (actor_id, action_type, target_profile_id)
    values (auth.uid(), 'retract_listing', p_attraction_id);
  end if;

  return v_row;
end;
$$;

grant execute on function public.retract_attraction(uuid) to authenticated;
