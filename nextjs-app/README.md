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
- `npm run typecheck` — `next typegen && tsc --noEmit`. `next typegen`
  (Next 16.4+) generates the ambient route types (`LayoutProps`,
  `PageProps`, etc.) into `.next/types` without doing a full build, so this
  works standalone on a fresh checkout and fails fast on a real type error
  without waiting on `npm run build` first.
- `npm run test:e2e` — all Playwright end-to-end tests (`e2e/`). First run
  `npx playwright install chromium` to download the browser binary. The
  suite drives `next dev` directly (`playwright.config.ts`'s `webServer`),
  reusing an already-running dev server on port 3000 if one exists.

  The suite is split into two tiers, matched by CI (`.github/workflows/nextjs-ci.yml`)
  to two separate jobs:

  - **Fixtures (default, no `@live` tag)** — `npm run test:e2e:fixtures`.
    Covers `TripHeader` layout stability (identical position/size across the
    trip/itinerary/dashboard/bookings tabs at 1440/1024/768/375px — no
    layout shift when switching tabs, the original bug this feature was
    built to fix), `TripSwitcher`'s popover/bottom-sheet responsive variants
    and `Escape` handling, `/auth` page rendering, `requireRealUserOrRedirect`
    (the no-session-protected-page-redirect test), and the `/profile/overview`
    guest view. These either drive `/dev-preview/trips/[tripId]/*` —
    fixture-data routes (`lib/dev-preview/fixtures.ts`) that bypass auth/DB
    entirely and 404 outside `NODE_ENV=development`/`test`, see
    `lib/dev-preview/guard.ts` — or hit routes that, for a session-less
    visit, never make a network call to Supabase at all (`supabase.auth.getUser()`
    returns `AuthSessionMissingError` synchronously with no session cookie to
    validate, empirically confirmed — elapsed ms: 0-1 against an unreachable
    placeholder host — for both `@supabase/supabase-js` and `@supabase/ssr`'s
    `createServerClient`). So this tier runs on **every PR** with the
    non-secret placeholder env vars already in the workflow — no Supabase
    project, real or test, required — and must never be skipped: it's the
    regression guard for the TripHeader layout bug and the primary signal
    most PRs will see.
  - **Live (tagged `@live`)** — `npm run test:e2e:live`. No specs currently
    need this tier — `requireRealUserOrRedirect` moved to fixtures above once
    proven it never touches the network for a session-less visit — so the
    script runs with `--pass-with-no-tests` to keep an empty tier green
    rather than failing on "no tests found". Gated in CI behind real
    Supabase credentials being present as repo secrets (Settings → Secrets
    and variables → Actions, same names as `.env.example`); skipped (not
    failed) otherwise. **Point these secrets at a separate, disposable test
    Supabase project — never the production project (`yshgjzmyapdepkapodno`,
    see `prisma/seed.ts`).** Tag any new spec that needs a real, reachable
    Supabase project (e.g. validating an actual authenticated session, not
    just a session-less `getUser()` call) with `@live` in its
    `test.describe`/`test` title so it lands in this tier, e.g.
    `test.describe("my feature @live", ...)`.

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

## Run locally against the live project

Auth (`/auth`, `/auth/callback`, `/auth/sign-out`) needs real GoTrue
endpoints — the local Supabase-CLI stack above has its own isolated `auth`
schema but isn't wired to the OAuth apps' real client IDs/secrets, so to
exercise the actual Google/GitHub sign-in flow during local development you
run `npm run dev` with `DATABASE_URL`/`DIRECT_URL` pointed at the local stack
(or the live one, per the usual rules above) but `NEXT_PUBLIC_SUPABASE_URL` /
`NEXT_PUBLIC_SUPABASE_ANON_KEY` pointed at the **live** Supabase project,
since that's where the OAuth provider apps are actually registered.

1. In `.env.local`, set `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY`
   to the live project's values (Supabase dashboard → Settings → API), and
   leave `NEXT_PUBLIC_SITE_URL="http://localhost:3000"` (the default in
   `.env.example`) — this is what `lib/auth/site-url.ts` uses to build the
   OAuth `redirectTo` and what `app/auth/callback/route.ts` redirects back to,
   so it must match the origin you're actually running `npm run dev` on.
2. In the live project's dashboard → **Authentication → URL Configuration**,
   add `http://localhost:3000/auth/callback` to the **Redirect URLs**
   allowlist (leave the existing production entries in place — this is an
   allowlist, not a single value). Without this, GoTrue rejects the OAuth
   callback with a redirect-URL-not-allowed error before it ever reaches our
   `/auth/callback` route.
3. Confirm these two project-level Auth toggles are already on (dashboard →
   Authentication → Providers / Sign In Methods) — both are one-time live
   project settings, not something to configure per-checkout:
   - **Allow anonymous sign-ins** — required for the guest session flow
     (`ensureAnonymousSession()`, Step 6+) and for `/auth/sign-out`'s
     guest-specific confirmation screen to ever be reachable.
   - **Allow manual linking of accounts** — required for a guest session to
     link a real Google/GitHub identity via the "Sign in to keep it" buttons
     on `/auth/sign-out` and the `identity_already_exists` recovery flow on
     `/auth`, instead of erroring.
4. `npm run dev`, then exercise the flows manually:
   - `/auth?redirect=%2Fprofile%2Foverview` → **Continue with Google/GitHub**
     → completes the real OAuth round trip → lands back on
     `/profile/overview` signed in.
   - `/auth/sign-out` while signed in as a real user → plain "Sign out?"
     confirmation → **Sign out** → back to `/`.
   - `/auth/sign-out` while on an anonymous/guest session → the data-loss
     warning screen → either **Sign in with Google/GitHub to keep it** (links
     the guest's data to the new identity) or **Sign out and permanently
     delete my data** (confirmed guest sign-out).
   - Visiting `/profile/overview` or `/trips/[tripId]` with no session at all
     renders a guest view (sign-in prompt) instead of crashing or
     redirecting — no OAuth app config needed for this one, it works against
     either the local or live `NEXT_PUBLIC_SUPABASE_URL`.
