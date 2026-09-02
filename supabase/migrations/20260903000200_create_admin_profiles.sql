-- Admin profile — extended data for the 3 admin-tier accounts (Super Admin,
-- Regional Admin, Content Moderator) plus the 2 additional job titles this
-- phase resolved onto existing permission tiers (Support Staff -> Content
-- Moderator's tier, Finance Admin -> its own new tier — see
-- 20260903000000_recreate_user_role_enum.sql's comment and
-- lib/core/auth/permissions.dart for the full reasoning). One row per admin
-- account, 1:1 with auth.users via user_id.
--
-- `role_title` (5 values, matches the source schema's dropdown exactly) is
-- DISTINCT from `profiles.role` (the 7-value enum permission checks
-- actually key on) — role_title is a display/audit label; the app maps it
-- onto a Role for enforcement (AdminRoleTitle.permissionRole in
-- lib/models/admin_profile.dart). Two admins can share role_title
-- 'support_staff' while both actually carry profiles.role =
-- 'content_moderator' for enforcement purposes.
--
-- Fields deliberately NOT built as real functionality yet, per this
-- phase's explicit scope:
--   - two_factor_enabled: stored, but NOT backed by any real MFA
--     enrollment/verification flow (Supabase MFA setup is out of scope for
--     this foundation phase) — the UI must show this honestly as
--     "Coming soon," never as a toggle that pretends to secure the account.
--   - permission_level (source schema's admin multi-select): NOT a stored
--     column — see AdminProfile.permissionLevel in the app model. It's
--     computed FROM the account's Role via the permission matrix, so there
--     is exactly one source of truth for what an admin can do, not two
--     that could drift apart.
--   - action_log / profiles_approved / disputes_handled: see
--     20260903000300_create_admin_action_log.sql — a real, working log
--     table with no caller yet, since no admin-action UI (approve listing,
--     moderate content, etc.) exists anywhere in this app — those all
--     depend on the 8 business profile types or a reviews system, both
--     out of scope this phase.
create table if not exists public.admin_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,

  role_title text not null
    check (role_title in ('super_admin', 'regional_admin', 'content_moderator', 'support_staff', 'finance_admin')),

  -- Multi-select of the 8 business types + Traveller + All — validated at
  -- the app layer against Role's own business-type list, same convention
  -- as Tour's guide_languages/highlights (no per-element DB check; this is
  -- descriptive metadata, not itself an enforcement point).
  managed_profile_types text[] not null default '{}',
  assigned_region text,
  account_status text not null default 'active'
    check (account_status in ('active', 'suspended', 'inactive')),

  -- Stored but not yet backed by a real MFA flow — see the doc comment above.
  two_factor_enabled boolean not null default false,
  -- System-logged: updated by the app itself on a successful admin sign-in
  -- (AuthProvider), not by a database trigger — auth.users lives in a
  -- protected schema this app doesn't otherwise touch.
  last_login timestamptz,
  last_login_ip text,

  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.admin_profiles enable row level security;

create policy "admins can view own profile"
  on public.admin_profiles for select
  using (auth.uid() = user_id);

-- "Manage other Admin accounts" is Super-Admin-only in the permissions
-- matrix — mirrored here so a Super Admin can actually see/manage other
-- admins' rows, not just their own.
create policy "super admins can view all admin profiles"
  on public.admin_profiles for select
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'super_admin'
    )
  );

create policy "admins can update own profile"
  on public.admin_profiles for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "super admins can update any admin profile"
  on public.admin_profiles for update
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'super_admin'
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'super_admin'
    )
  );

create policy "super admins can insert admin profiles"
  on public.admin_profiles for insert
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'super_admin'
    )
  );
