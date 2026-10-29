# ExploriFe (Next.js)

Next.js/Prisma/PostgreSQL rewrite of the ExploriFe Flutter app. See
`../MIGRATION_PLAN.md` for the full audit, architecture decisions, data
model, and step-by-step migration plan — read that first, not this file.

## Status

Step 3 (Database) done — see `MIGRATION_PLAN.md` §7. Still no real routes
beyond the scaffold; the database layer and its authorization guards are now
real and live:

- `app/` — App Router routes (placeholder `/` only so far)
- `components/ui` — generic presentational primitives
- `components/features` — domain-grouped feature components
- `lib/db.ts` — shared Prisma client singleton
- `prisma/schema.prisma` — hand-built from live-DB SQL introspection (no
  `prisma db pull` — no direct DB password available, see
  `MIGRATION_PLAN.md` §3/§7); `prisma generate`/`validate`/`tsc` all pass
  against it
- `prisma/migrations/` — `0_init` (baseline, resolved locally — empty diff
  confirmed `schema.prisma` matched the live DB exactly) and
  `1_hike_tracks_fields` (Risk #1's additive `hike_tracks` columns) are both
  **applied**; `prisma migrate status` is clean. Both were run by the user
  locally, never the agent, per `MIGRATION_PLAN.md` §7/"Migration safety
  rules" below. `0_init/migration.sql` is now committed to the repo (generated
  after the fact from `schema.prisma` via `prisma migrate diff --from-empty`
  against a pre-hike_tracks snapshot, so it replays correctly in sequence with
  `1_hike_tracks_fields`), so other checkouts see the real migration history
  instead of a missing/drifted one.
- `prisma/db-notes.sql` — reference doc for live DB-side behavior Prisma
  can't express (generated columns, `auth.uid()`-dependent triggers)
- `lib/auth/permissions.ts` — centralized authorization, including the three
  `auth.uid()`-dependent trigger protections from `prisma/db-notes.sql` §2
  (`assertCanChangeProfileRole`, `assertCanVerifyAttraction`,
  `assertCanVerifyRestaurant`) with unit tests in
  `lib/auth/permissions.test.ts` (`npx vitest run`); see `MIGRATION_PLAN.md`
  §3a for what each remaining function becomes
- `lib/supabase/` — `@supabase/ssr` browser/server clients + session-refresh
  helper (wired into `proxy.ts`)
- `lib/server/` — Server Actions / server-only data access, organized by
  domain (empty until Step 3a — not yet wired to `lib/auth/permissions.ts`)

## Getting started

```bash
cp .env.example .env.local   # fill in real values — see "Environment variables" below
npm install
npm run dev
```

## Testing

- `npm run test` (or `npm run test:watch`) — Vitest unit tests for
  `lib/server/`, `lib/auth/`, `lib/format/`.
- `npm run test:e2e` — Playwright end-to-end tests (`e2e/`) covering the
  trip routing shell: `TripHeader` renders at an identical position/size
  across the trip/itinerary/dashboard/bookings tabs at 1440/1024/768/375px
  (no layout shift when switching tabs — the original bug this feature was
  built to fix), `TripSwitcher` opens as a popover at >=768px and a bottom
  sheet at <768px, and `Escape` closes either and returns focus to the
  trigger button. First run `npx playwright install chromium` to download
  the browser binary. These tests drive `/dev-preview/trips/[tripId]/*` —
  fixture-data routes (`lib/dev-preview/fixtures.ts`) that bypass auth/DB
  entirely and 404 outside `NODE_ENV=development`/`test` (see
  `lib/dev-preview/guard.ts`) — so they never touch the live database and
  never ship in a production build. The suite drives `next dev` directly
  (`playwright.config.ts`'s `webServer`), reusing an already-running dev
  server on port 3000 if one exists.

Other scripts: `npm run lint`, `npm run format`, `npm run db:pull`,
`npm run db:generate`, `npm run db:migrate`.

## Environment variables

`prisma.config.ts` loads `.env` then `.env.local` on top of it (local wins —
same precedence Next.js itself uses), because once a `prisma.config.ts`
exists the Prisma CLI stops doing its own `.env` loading entirely. In
practice: put real values in `.env.local` (gitignored, per `.gitignore`'s
`.env*` entry) and both `npm run dev` and standalone `npx prisma <command>`
pick them up — no manual `export DATABASE_URL=...` needed.

Two separate Postgres connection strings are required (see `.env.example`
for the full annotated list, `MIGRATION_PLAN.md` §5 for the full rationale):

- **`DATABASE_URL`** — the **transaction pooler** (Supabase's PgBouncer,
  port `6543`, `?pgbouncer=true`). Used by the Prisma client at runtime for
  all normal app query traffic.
- **`DIRECT_URL`** — the **session pooler** (same pooler host, port `5432`,
  no `?pgbouncer=true`). Used only by `prisma migrate`/`prisma db pull`/
  `prisma migrate diff`, which need a full, non-transaction-pooled session.

  This is deliberately **not** Supabase's literal "direct connection" host
  (`db.[project-ref].supabase.co`) — that host is **IPv6-only on the free
  plan** and unreachable from most networks and CI runners. The session
  pooler gives the Prisma CLI the same non-pooled-session capability over
  IPv4, which is why `DIRECT_URL` points at the pooler host too, just on a
  different port/mode than `DATABASE_URL`.

## Migration safety rules

The only Postgres instance this project currently talks to by default is the
live Supabase-hosted project. These rules exist to keep local iteration from
ever touching it destructively — see `MIGRATION_PLAN.md` §7 for the full
rationale.

- **Never run `prisma migrate dev` or `prisma migrate reset` against the
  live project.** Both can drop/recreate database objects to reconcile
  drift, which is unacceptable against real data. The only safe path to
  change the live schema is:
  1. `prisma migrate diff` (live DB → `prisma/schema.prisma`) to generate a
     SQL script of the intended change.
  2. Review that SQL by hand (watch for `DROP`, `ALTER COLUMN`, or
     constraint changes you didn't intend).
  3. Apply it with `prisma migrate deploy`.
- **Never write to Prisma's `_prisma_migrations` tracking table via the
  Supabase MCP or any other indirect/automated channel.** Baselining
  (marking the already-existing live schema as "applied" in Prisma's
  migration history) is done locally by a human running
  `prisma migrate resolve --applied <migration>`, not by an agent.
- **The seed script (`prisma/seed.ts`) hard-refuses to run** against
  anything that isn't a `localhost`/`127.0.0.1` `DATABASE_URL`, or that
  references the live project's ref. There is no bypass env var — if you
  need to seed data, do it against the local dev database below.

## Local development database

To safely run `prisma migrate dev`, `npx prisma db seed`, or anything else
that writes schema/data without any risk to the live project, run against a
local Postgres instance provisioned by the Supabase CLI. This also gives you
a real local `auth` schema (`auth.users` etc.), which the live-only
`DATABASE_URL` above can't provide for local experimentation.

1. Install the Supabase CLI if you don't have it (see
   https://supabase.com/docs/guides/local-development).
2. From the repo root (where `supabase/` config lives, or run `supabase init`
   once if it doesn't exist yet), start the local stack:
   ```bash
   supabase start
   ```
   This prints local connection details, including a Postgres URL (default
   `postgresql://postgres:postgres@127.0.0.1:54322/postgres`).
3. In your local `.env.local`, point `DATABASE_URL`/`DIRECT_URL` at that
   local instance instead of the live project (see the commented-out example
   in `.env.example`'s "Local development database" section). Use one set of
   values or the other — never mix a local `DATABASE_URL` with a live
   `DIRECT_URL` or vice versa.
4. Now `prisma migrate dev`, `npx prisma db seed`, etc. are safe to run — they
   only ever touch the local stack.
5. `supabase stop` to tear the local stack down when you're done.
