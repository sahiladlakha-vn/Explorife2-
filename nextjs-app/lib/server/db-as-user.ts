import "server-only";
import { prisma } from "@/lib/db";
import { Prisma } from "@/lib/generated/prisma/client";

/**
 * Runs a Prisma interactive transaction with the acting user's identity
 * visible to Postgres triggers, closing a real correctness gap in every
 * write path that touches a trigger-locked column
 * (`profiles.role`; `{attractions,restaurants}.verification_status` /
 * `verified_by` / `verified_at` — see `prisma/db-notes.sql` §2).
 *
 * ## The problem this fixes
 *
 * `lib/db.ts`'s `prisma` client talks to Postgres directly over
 * `DATABASE_URL`, never through PostgREST. The live lock triggers
 * (`lock_profile_role_field`, `lock_attraction_verification_fields`,
 * `lock_restaurant_verification_fields`) all gate on `auth.uid()` /
 * `auth.role()`, which are just thin wrappers around
 * `current_setting('request.jwt.claim.sub' / 'claim.role', true)` (falling
 * back to parsing `current_setting('request.jwt.claims', true)::jsonb`). On a
 * plain Prisma connection none of those GUCs are ever set, so `auth.uid()`
 * resolves to `NULL` for every Prisma-issued query — including ones issued by
 * a real, authorized super_admin. Each trigger's own `exists(...)` check
 * against `profiles.id = auth.uid()` deterministically fails, and the
 * trigger reverts the locked column(s) as if the caller were unauthorized,
 * even when they aren't. Critically, the UPDATE itself still *succeeds*
 * (the trigger reverts a column, it doesn't raise), so without an explicit
 * check a caller walks away believing a write landed when it silently
 * didn't — and in `updateUserRole`'s case, `admin_action_log` would record a
 * role change that never actually happened.
 *
 * ## The fix
 *
 * `set_config('request.jwt.claims', <json>, true)` populates the same GUC
 * `auth.uid()`/`auth.role()` read, with its third argument (`is_local =
 * true`) making the setting transaction-local — equivalent to `SET LOCAL`,
 * automatically and unconditionally cleared at `COMMIT`/`ROLLBACK`. Setting
 * it as the first statement inside a `prisma.$transaction(async (tx) => ...)`
 * callback means every later statement issued through that same `tx` inside
 * the same Postgres transaction sees the claim, and nothing outside this
 * transaction — not even a later query reusing the same pooled connection —
 * ever can.
 *
 * That transaction-scoping is not just tidy, it's load-bearing:
 * `DATABASE_URL` is the Supabase *transaction-pooler* connection
 * (`:6543?pgbouncer=true`, see `.env.example` and `lib/db.ts`'s top comment).
 * Under transaction-mode pooling a physical backend connection is handed to
 * one logical transaction for that transaction's duration only, then
 * returned to the pool and handed to a *different* logical transaction
 * (possibly a different request, a different user) next. A session-level
 * `SET` (no `true` argument) would leak the acting user's claims onto
 * whichever unrelated query happens to reuse that backend connection next —
 * exactly the bug class transaction-mode pooling exists to make dangerous.
 * `set_config(..., true)` is scoped to avoid that: it rides along with the
 * Postgres transaction, not the backend connection, so it's safe to use
 * against a pooled connection without any special pooler configuration.
 *
 * ## What this does NOT do
 *
 * This does not re-check authorization — callers must still run their own
 * `assertCan*`/role checks (as `updateUserRole`, `setAttractionVerification`,
 * `setRestaurantVerification` already do) *before* calling this, exactly as
 * before. All this does is make the *real, already-authorized* actor visible
 * to Postgres, so a legitimate write no longer looks unauthorized to the
 * trigger. It also does not, by itself, guarantee a locked-column write
 * stuck — callers must still re-read the row inside the same `tx` after
 * writing and confirm the locked field actually changed, since a bug in this
 * helper, a role mismatch, or an actor who turns out not to really hold the
 * role they were asserted to hold could all still trip the trigger's revert
 * branch. See the re-read-and-throw guards in `updateUserRole`,
 * `setAttractionVerification`, and `setRestaurantVerification`.
 *
 * @param actingUserId - The authenticated actor's `profiles.id` /
 *   `auth.users.id`. This becomes `auth.uid()` inside the transaction. Must
 *   be the real caller's id, never a caller-supplied value, or this
 *   reintroduces the exact spoofing risk the trigger exists to prevent.
 * @param fn - The transactional work to run. Receives the same
 *   `Prisma.TransactionClient` the claim was set on; every query that needs
 *   `auth.uid()`/`auth.role()` populated MUST go through this `tx`, not the
 *   top-level `prisma` client.
 * @param options - Forwarded to `prisma.$transaction` (e.g.
 *   `{ isolationLevel: Prisma.TransactionIsolationLevel.Serializable }`).
 */
export async function runAsUser<T>(
  actingUserId: string,
  fn: (tx: Prisma.TransactionClient) => Promise<T>,
  options?: { isolationLevel?: Prisma.TransactionIsolationLevel; maxWait?: number; timeout?: number },
): Promise<T> {
  return prisma.$transaction(async (tx) => {
    const claims = JSON.stringify({ sub: actingUserId, role: "authenticated" });
    await tx.$executeRaw`select set_config('request.jwt.claims', ${claims}, true)`;
    return fn(tx);
  }, options);
}
