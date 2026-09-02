-- Replaces the existing 3-value `user_role` enum (traveler, guide, admin —
-- predates this migration history, set up early for seed/demo data, never
-- read by any app code — confirmed via a repo-wide grep before writing this)
-- with the 7-value taxonomy the real Roles & Permissions matrix defines:
-- traveler, guide, business_owner, content_moderator, regional_admin,
-- super_admin, finance_admin.
--
-- finance_admin is the one value not in the matrix as originally read: the
-- Admin sheet's Role/Title dropdown has 5 titles (Super Admin, Regional
-- Admin, Content Moderator, Support Staff, Finance Admin) but the matrix
-- only defined permission columns for 3. Resolved: Support Staff shares
-- Content Moderator's permission tier (no new enum value needed — it's
-- just a `role_title` label, see admin_profiles below); Finance Admin gets
-- its own tier (own-only payments/payouts + own-only analytics, nothing
-- else) since nothing else in the matrix matches that shape.
--
-- 13 real profiles rows exist today (6 seeded 'guide' test accounts, 5
-- 'traveler' rows, 1 'admin' row). Mapped: admin -> super_admin (same
-- account already hardcoded as the sheet-sync owner elsewhere in this
-- app — it IS the platform's sole full-control account), guide -> guide,
-- traveler -> traveler. A clean recreation (not ALTER TYPE ADD VALUE) was
-- chosen deliberately: Postgres can't drop/rename an enum value across a
-- dependent column in one step, and leaving the old 'admin' label
-- permanently in the type (unused forever) would be exactly the lingering
-- ambiguity this phase exists to remove.
create type public.user_role_new as enum (
  'traveler',
  'guide',
  'business_owner',
  'content_moderator',
  'regional_admin',
  'super_admin',
  'finance_admin'
);

-- Three `stories` RLS policies reference profiles.role directly (found only
-- by attempting this migration — no Dart code references it, but these
-- three do) — must be dropped before the column they depend on can be
-- dropped, then recreated below against the new enum with the corrected
-- predicate: the matrix's "Moderate reviews/content" row grants this to
-- Content Moderator, Regional Admin, and Super Admin (not Super Admin
-- alone, which is what the old single-value 'admin' check collapsed it to).
drop policy if exists "stories_select_admin" on public.stories;
drop policy if exists "stories_update_admin" on public.stories;
drop policy if exists "stories_delete_admin" on public.stories;

alter table public.profiles add column role_new public.user_role_new;

update public.profiles set role_new = (
  case role::text
    when 'admin' then 'super_admin'
    when 'guide' then 'guide'
    else 'traveler'
  end
)::public.user_role_new;

alter table public.profiles alter column role_new set not null;
alter table public.profiles alter column role_new set default 'traveler'::public.user_role_new;

alter table public.profiles drop column role;
alter table public.profiles rename column role_new to role;

drop type public.user_role;
alter type public.user_role_new rename to user_role;

-- Recreated against the new enum, same policy names, corrected predicate
-- (see the drop above for why this is content_moderator/regional_admin/
-- super_admin, not just super_admin).
create policy "stories_select_admin"
  on public.stories for select
  using (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid()
        and profiles.role in ('content_moderator', 'regional_admin', 'super_admin')
    )
  );

create policy "stories_update_admin"
  on public.stories for update
  using (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid()
        and profiles.role in ('content_moderator', 'regional_admin', 'super_admin')
    )
  );

create policy "stories_delete_admin"
  on public.stories for delete
  using (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid()
        and profiles.role in ('content_moderator', 'regional_admin', 'super_admin')
    )
  );
