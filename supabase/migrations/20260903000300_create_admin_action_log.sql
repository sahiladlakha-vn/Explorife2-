-- Real, working audit log for admin actions — the "Action Log" field from
-- the Admin profile schema. Built now even though nothing in this app
-- calls it yet: every admin action the permissions matrix defines
-- (approve/reject a listing, verify a license, moderate content, suspend/
-- ban an account, manage a payment, assign/change a role) depends on
-- either the 8 business profile types or a reviews/moderation system, both
-- explicitly out of scope this phase — there is no admin-action UI
-- anywhere in this app yet to generate a real entry from. The write path
-- itself is fully real and tested (see AdminActionLogRepository), so a
-- future phase's admin actions have a ready, working log to call into
-- rather than a schema field that needs building from scratch later.
--
-- `profiles_approved`/`disputes_handled` (the Admin schema's two counter
-- fields) are NOT separate stored columns — they're computed by counting
-- this table (see AdminActionLogRepository.countActions), so there's one
-- source of truth for "how many actions has this admin taken," not a
-- counter that can drift from the log it's supposedly summarizing.
create table if not exists public.admin_action_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users (id) on delete cascade,
  action_type text not null check (action_type in (
    'approve_listing', 'reject_listing',
    'verify_license',
    'moderate_content',
    'suspend_account', 'ban_account',
    'manage_payment',
    'assign_role'
  )),
  -- Not FK-constrained: the target can be a listing/business profile from
  -- any of the future 8 profile types, or a traveller/admin account — no
  -- single table to reference yet, same "validate at the app layer, not a
  -- DB constraint" convention this app already uses for Gem/Tour category
  -- values.
  target_profile_id uuid,
  details jsonb,
  created_at timestamptz not null default now()
);

alter table public.admin_action_log enable row level security;

-- An admin can only log an action as themselves — there's no service-role
-- backend writing this, the acting admin's own client performs the insert.
create policy "admins can log their own actions"
  on public.admin_action_log for insert
  with check (auth.uid() = actor_id);

create policy "admins can view their own action log"
  on public.admin_action_log for select
  using (auth.uid() = actor_id);

-- "Manage other Admin accounts" / platform-wide oversight is Super-Admin-only.
create policy "super admins can view all action logs"
  on public.admin_action_log for select
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'super_admin'
    )
  );
