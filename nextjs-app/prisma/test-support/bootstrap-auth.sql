-- Minimal stand-in for Supabase's `auth` schema, used ONLY by the CI
-- integration-test Postgres service container (a plain `postgres` Docker
-- image, not a real Supabase project — see
-- .github/workflows/nextjs-ci.yml's `db-trigger-integration` job). Never run
-- this against the live project: `auth.*` already exists there and is owned
-- by Supabase (see prisma.config.ts's `tables.external` list, which is the
-- reason `prisma/migrations/0_init/migration.sql` contains no `CREATE
-- SCHEMA/TABLE "auth"...` of its own — this file fills that gap only for a
-- from-scratch test database).
--
-- Provides just enough of `auth.users`/`auth.uid()`/`auth.role()` for:
--   1. migration.sql's `REFERENCES "auth"."users"("id")` FK constraints to
--      apply cleanly against a fresh database (run this file BEFORE
--      `prisma migrate deploy`), and
--   2. the three lock trigger functions (lock-triggers.sql, applied AFTER
--      `prisma migrate deploy`) to resolve `auth.uid()`/`auth.role()` the
--      same way they do on the live project, so
--      `lib/server/db-as-user.ts`'s `runAsUser()` can be exercised against
--      real trigger behavior instead of a mock.
--
-- `auth.uid()`/`auth.role()` below are Supabase's own standard, open-source
-- definitions (verbatim from supabase/postgres's initial-schema migration,
-- the same shape confirmed against the live `yshgjzmyapdepkapodno` project
-- during this session's Finding-0 trigger verification) — not a
-- simplification of them, so this harness tests the real GUC-resolution
-- logic `runAsUser`'s `set_config('request.jwt.claims', ..., true)` call
-- depends on.

create schema if not exists auth;

-- Columns limited to what prisma/schema.prisma's `User` model declares
-- (`id`, `isAnonymous` @map("is_anonymous")) — every other real
-- `auth.users` column (email, encrypted_password, ...) is Auth-internal and
-- untouched by Prisma or by any code under test here.
create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  is_anonymous boolean not null default false
);

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select
    coalesce(
      nullif(current_setting('request.jwt.claim.sub', true), ''),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
    )::uuid
$$;

create or replace function auth.role()
returns text
language sql
stable
as $$
  select
    coalesce(
      nullif(current_setting('request.jwt.claim.role', true), ''),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
    )::text
$$;
