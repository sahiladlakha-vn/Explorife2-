# Google Sheets → Supabase content-sync runbook

Operational notes for the three Google-Sheets-driven content-sync pipelines
(Apps Script → Supabase RPC, documented in full in `MIGRATION_PLAN.md` §6
Risk #10 and §3a's "Out of scope" row): `gem-sheet-sync.gs` →
`upsert_gem_from_sheet`, `tour-sheet-sync.gs` → `upsert_tour_from_sheet`, and
`collection-sheet-sync.gs` → `upsert_curated_collection_from_sheet`. Each
script calls its RPC directly over PostgREST using the project's anon/service
key — none of this goes through the Next.js app or Prisma, and none of it is
part of this migration's scope (Risk #10: left running as-is).

## Security invariants — re-check after any database change

These RPCs run `SECURITY DEFINER` and are callable directly by the Apps
Script, so they sit outside the Next.js app's own authorization layer
(`lib/auth/permissions.ts`) and outside the three `auth.uid()`-dependent
"lock" triggers the Next.js correctness fix in `nextjs-app/lib/server/
db-as-user.ts` is built around (see `nextjs-app/prisma/db-notes.sql` §2 and
`MIGRATION_PLAN.md` §3a for the full writeup of those triggers and why a
Prisma-issued write needs `runAsUser()` to pass them). A schema change that
touches `profiles`, `attractions`, or `restaurants` — including anything
applied directly against the live database outside Prisma, which is exactly
how the sheet-sync RPCs themselves operate — can silently drop or disable
one of these triggers without the Next.js test suite ever seeing it (the
unit tests mock Prisma and can't observe trigger behavior; only
`nextjs-app/lib/server/integration/trigger-behavior.integration.test.ts`,
run against a real Postgres, exercises the real trigger SQL, and only in CI
against the disposable test database — never against the live project).

After any live-database change (migration, manual DDL, Supabase dashboard
edit, or a sync script change that touches these tables), confirm all three
triggers still exist and are enabled:

```sql
select event_object_table, trigger_name, action_timing, event_manipulation
from information_schema.triggers
where trigger_schema = 'public'
  and trigger_name in (
    'profiles_lock_role_field',
    'attractions_lock_verification_fields',
    'restaurants_lock_verification_fields'
  );
```

Expect exactly three rows back (`BEFORE` / `UPDATE`, one per table). If a row
is missing, or if `pg_trigger.tgenabled <> 'O'` for any of them (e.g. via
`select tgname, tgenabled from pg_trigger where tgname in (...)`), that
table's role/verification fields are no longer protected against a direct
(non-Next.js) write — treat it as a live security regression, not a
sheet-sync bug, and escalate before touching the sync scripts further.
