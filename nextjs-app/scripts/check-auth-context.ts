// Read-only diagnostic for `lib/server/db-as-user.ts`'s `runAsUser()` helper.
// Run directly: `npx tsx scripts/check-auth-context.ts` (not through the
// Prisma CLI or Next.js, so it loads `.env`/`.env.local` itself below,
// matching `prisma.config.ts`'s exact order/precedence).
//
// What this checks, and why: `runAsUser()` makes the acting user visible to
// Postgres's row-level `auth.uid()` (and therefore to the
// `lock_profile_role_field`/`lock_attraction_verification_fields`/
// `lock_restaurant_verification_fields` triggers) by running
//   select set_config('request.jwt.claims', <json with "sub">, true)
// as the first statement inside a `prisma.$transaction(...)` callback. The
// `true` third argument makes this a transaction-local
// (`SET LOCAL`-equivalent) setting that Postgres clears at COMMIT/ROLLBACK.
// That's the right primitive *if* DATABASE_URL's pooled connection is never
// shared, mid-setting, with a different transaction — which is exactly what
// Supabase's transaction-mode pooler (PgBouncer, port 6543,
// `?pgbouncer=true`) does: it hands a physical connection to a transaction
// for that transaction's duration only, then returns it to the pool. This
// script empirically confirms that handoff is clean:
//
//   1. Open transaction #1, set `request.jwt.claims` with a random UUID as
//      `sub`, and read `auth.uid()` back inside the SAME transaction —
//      expected to match the UUID we set.
//   2. Open a completely SEPARATE transaction #2 (no claim set at all) and
//      read `auth.uid()` — expected to be NULL. If it instead showed
//      transaction #1's UUID, that would mean the transaction-local setting
//      leaked across pooled connections/transactions, which would be a
//      serious authorization bug (one request's acting-user identity
//      bleeding into another's). This is the actual regression this script
//      exists to catch.
//
// Deliberately does ZERO writes (no `INSERT`/`UPDATE`/`DELETE`, no DDL) —
// `select set_config(...)` and `select auth.uid()` only — so, unlike
// `prisma/seed.ts` or `lib/server/integration/db-guard.ts`, this has no
// production-database refusal guard: the whole point is to be safe to run
// against whatever DATABASE_URL points at, including the live project's
// pooler, to prove the pooler itself behaves correctly there.
import { config as loadEnv } from "dotenv";
loadEnv({ path: ".env" });
loadEnv({ path: ".env.local" });

import { randomUUID } from "node:crypto";
import { PrismaClient } from "../lib/generated/prisma/client";

const prisma = new PrismaClient();

async function checkOneTransaction(label: string, claimSub: string | null) {
  return prisma.$transaction(async (tx) => {
    if (claimSub !== null) {
      const claims = JSON.stringify({ sub: claimSub, role: "authenticated" });
      await tx.$executeRaw`select set_config('request.jwt.claims', ${claims}, true)`;
    }

    const rows = await tx.$queryRaw<{ uid: string | null }[]>`select auth.uid() as uid`;
    const uid = rows[0]?.uid ?? null;

    console.log(`[${label}] claim set: ${claimSub ?? "(none)"}`);
    console.log(`[${label}] auth.uid(): ${uid ?? "NULL"}`);

    return uid;
  });
}

async function main() {
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) {
    throw new Error("DATABASE_URL is not set.");
  }

  let hostname: string;
  try {
    hostname = new URL(databaseUrl).hostname;
  } catch {
    throw new Error(`DATABASE_URL ("${databaseUrl}") isn't a parseable URL.`);
  }
  console.log(`Target database host: ${hostname}`);
  console.log(`Pooled (expect port 6543 / pgbouncer=true for a real pooler check): ${databaseUrl.includes("6543") || databaseUrl.includes("pgbouncer")}`);
  console.log("");

  const claimSub = randomUUID();
  console.log(`Random UUID used as "sub": ${claimSub}`);
  console.log("");

  // Transaction #1: set the claim, read it back in the SAME transaction.
  const uid1 = await checkOneTransaction("txn 1 (claim set)", claimSub);
  const matched = uid1 === claimSub;
  console.log(`[txn 1] matches the UUID we set? ${matched ? "YES" : "NO"}`);
  console.log("");

  // Transaction #2: a fresh transaction, no claim set at all. If the pooler
  // handed back the SAME physical connection transaction #1 used, and the
  // `set_config(..., true)` setting somehow survived past that commit, this
  // would incorrectly show transaction #1's UUID instead of NULL.
  const uid2 = await checkOneTransaction("txn 2 (fresh, no claim)", null);
  const leaked = uid2 !== null;
  console.log(`[txn 2] leaked a value from txn 1 across the pool? ${leaked ? "YES — BUG" : "no (NULL as expected)"}`);
  console.log("");

  console.log("Summary:");
  console.log(`  txn 1 auth.uid() matched the set claim: ${matched ? "PASS" : "FAIL"}`);
  console.log(`  txn 2 auth.uid() is NULL (no cross-transaction leak): ${!leaked ? "PASS" : "FAIL"}`);

  if (!matched || leaked) {
    process.exitCode = 1;
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
