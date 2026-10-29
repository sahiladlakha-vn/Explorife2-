import "server-only";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";

/**
 * Service-role Supabase Admin API client — NOT for table reads/writes
 * (`lib/db.ts`'s Prisma client is the sole table-access path; see its own
 * doc comment and `lib/server/write-guard.test.ts`'s `.from()` detector,
 * which treats ANY direct Supabase table write, service-role or not, as out
 * of place in this codebase). This client exists only for Supabase Auth
 * Admin API calls that need visibility into `auth.users` columns Prisma's
 * `User` model deliberately doesn't model — see that model's doc comment in
 * `prisma/schema.prisma`: "every other Auth-internal column... is accessed
 * exclusively via @supabase/ssr, never through Prisma." The Admin API is the
 * carve-out for the one thing `@supabase/ssr`'s request-scoped client can't
 * do: look up a column (like `is_anonymous`) on some OTHER user's row, not
 * just the caller's own session.
 *
 * Minimal and narrowly scoped on purpose: right now the only caller is
 * `lib/auth/permissions.ts`'s `isAnonymousGuest()` (used by
 * `updateUserRole()`'s anonymous-guest-target guard). The fuller Admin API
 * surface already anticipated in `.env.example` and MIGRATION_PLAN.md §3a
 * (`inviteUserByEmail`/`deleteUser`, ported from
 * `supabase/functions/admin-create-user` into a future
 * `lib/server/admin/users.ts`) is a separate, larger task — not built here,
 * but that future module should reuse this factory rather than add a second
 * one.
 *
 * Plain `@supabase/supabase-js` (not `@supabase/ssr`): there's no
 * request-scoped session or cookies involved here — the service-role key
 * itself is the only credential, so `autoRefreshToken`/`persistSession` are
 * explicitly disabled.
 */
export function createAdminClient() {
  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );
}
