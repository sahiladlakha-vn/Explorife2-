# lib/server

Server Actions and server-only data-access functions, organized by domain
(e.g. `admin/users.ts`, `splits/groups.ts`, `listings/attractions.ts`) —
this is where MIGRATION_PLAN.md §3a's function -> TypeScript-home mapping
lands. Every exported function here must call into `lib/auth/permissions.ts`
before reading or writing via `lib/db.ts`'s Prisma client, since Prisma
bypasses RLS (see MIGRATION_PLAN.md §0). Populated starting in Step 3a.
