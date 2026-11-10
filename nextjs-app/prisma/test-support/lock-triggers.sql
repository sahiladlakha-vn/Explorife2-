-- The three `auth.uid()`-gated BEFORE UPDATE "lock" triggers from the live
-- Supabase project, applied here as raw SQL so the CI integration-test
-- Postgres container reproduces the exact behavior
-- `lib/server/db-as-user.ts` (`runAsUser`) and its callers
-- (`updateUserRole` in lib/server/profiles.ts, `setAttractionVerification`
-- in lib/server/attractions.ts, `setRestaurantVerification` in
-- lib/server/restaurants.ts) are built against.
--
-- These triggers have no Prisma migration of their own — they were never
-- created by `prisma migrate`, only documented (see prisma/db-notes.sql §2,
-- itself pulled from the live DB via `pg_get_functiondef`). This file is the
-- one place their SQL is exercised anywhere outside the live project. Run
-- this AFTER `prisma migrate deploy` (it references `public.profiles` /
-- `public.attractions` / `public.restaurants`, which that migration creates)
-- and AFTER bootstrap-auth.sql (it calls `auth.uid()`).
--
-- Bodies copied verbatim from the live `yshgjzmyapdepkapodno` project
-- (confirmed via Supabase MCP `pg_get_functiondef` introspection during this
-- session's Finding-0 verification) — not reconstructed from the db-notes.sql
-- summary, so a drift between that summary and the real function body would
-- still be caught by running these tests against the live project's actual
-- definitions.

create or replace function public.lock_profile_role_field()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.role <> old.role and not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'super_admin'::user_role
  ) then
    new.role := old.role;
  end if;
  return new;
end;
$function$;

drop trigger if exists profiles_lock_role_field on public.profiles;
create trigger profiles_lock_role_field
  before update on public.profiles
  for each row
  execute function public.lock_profile_role_field();

create or replace function public.lock_attraction_verification_fields()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not exists (
    select 1 from public.profiles
    where profiles.id = auth.uid()
      and profiles.role in ('content_moderator', 'regional_admin', 'super_admin')
  ) then
    new.verification_status := old.verification_status;
    new.verified_by := old.verified_by;
    new.verified_at := old.verified_at;
  end if;
  new.updated_at := now();
  return new;
end;
$function$;

drop trigger if exists attractions_lock_verification_fields on public.attractions;
create trigger attractions_lock_verification_fields
  before update on public.attractions
  for each row
  execute function public.lock_attraction_verification_fields();

create or replace function public.lock_restaurant_verification_fields()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not exists (
    select 1 from public.profiles
    where profiles.id = auth.uid()
      and profiles.role in ('content_moderator', 'regional_admin', 'super_admin')
  ) then
    new.verification_status := old.verification_status;
    new.verified_by := old.verified_by;
    new.verified_at := old.verified_at;
  end if;
  new.updated_at := now();
  return new;
end;
$function$;

drop trigger if exists restaurants_lock_verification_fields on public.restaurants;
create trigger restaurants_lock_verification_fields
  before update on public.restaurants
  for each row
  execute function public.lock_restaurant_verification_fields();
