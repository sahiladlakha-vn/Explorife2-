-- Extends the existing admin_action_log (not a new admin_audit_log table —
-- confirmed via its migration + live RLS that this already is exactly that
-- table, just missing two action types, typed old/new-role columns, and a
-- client-side insert path that turned out to be dead code) to cover the
-- Users page's "create user" / "resend invite" actions.

alter table public.admin_action_log
  add column if not exists old_role public.user_role,
  add column if not exists new_role public.user_role;

alter table public.admin_action_log drop constraint admin_action_log_action_type_check;
alter table public.admin_action_log
  add constraint admin_action_log_action_type_check
  check (action_type = any (array[
    'approve_listing', 'reject_listing',
    'verify_license',
    'moderate_content',
    'suspend_account', 'ban_account',
    'manage_payment',
    'assign_role',
    'retract_listing',
    'create_user',
    'resend_invite'
  ]));

-- AdminActionLogRepository.logAction (the one client-side direct-insert
-- path) has zero call sites anywhere in the app (grep-confirmed) — this
-- policy was always dead code, not a real write path. The only writers are,
-- and will remain, the SECURITY DEFINER functions below and in the
-- companion migrations, which insert as the table owner and bypass RLS
-- entirely regardless of this policy.
drop policy if exists "admins can log their own actions" on public.admin_action_log;

-- No client of any kind should be able to write or edit this table at all
-- going forward. No UPDATE/DELETE policy has ever existed for any role, so
-- this is belt-and-suspenders on top of RLS, not a behavior change.
revoke insert, update, delete on public.admin_action_log from anon, authenticated;
revoke select on public.admin_action_log from anon;

-- Consolidate the two existing SELECT policies (self-only, or
-- super_admin-sees-all) into one: every admin-tier role can read the full
-- log, matching "admins can read it" from the feature spec.
drop policy if exists "admins can view their own action log" on public.admin_action_log;
drop policy if exists "super admins can view all action logs" on public.admin_action_log;

create policy "admin tier can view all action logs"
  on public.admin_action_log for select
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = any (array[
          'content_moderator', 'regional_admin', 'super_admin', 'finance_admin'
        ]::user_role[])
    )
  );
