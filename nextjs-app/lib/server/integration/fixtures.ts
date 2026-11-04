// Seeding helpers for the real-Postgres integration suite
// (`lib/server/integration/*.integration.test.ts`). These call
// `prisma.profile.create` / `prisma.attraction.create` /
// `prisma.restaurant.create` directly, which `lib/server/write-guard.test.ts`
// normally forbids outside `lib/server/{profiles,attractions,restaurants}.ts`
// — this file (and the integration test files themselves) are the two
// explicitly reviewed, allow-listed exceptions (see that test's
// `ALLOWED_RELATIVE_PATHS`), because:
//
//   1. `assertIntegrationTestDatabaseIsSafe()` (./db-guard.ts) is called by
//      every integration test file before any of these run, so this code can
//      only ever execute against a disposable loopback/CI Postgres
//      container, never the live project.
//   2. These are `create()` calls building known-good fixture rows for a
//      test to then exercise through the real, guarded write paths
//      (`updateUserRole`, `setAttractionVerification`,
//      `setRestaurantVerification`) — not a write path of their own that the
//      guard needs to catch.
//
// `auth.users` rows are seeded via `prisma.user.create` — unrestricted,
// since `user` isn't one of the three guarded models.
import { randomUUID } from "node:crypto";
import { prisma } from "@/lib/db";
import type { Role } from "@/lib/auth/permissions";

/** Inserts a bare `auth.users` row (this harness's stand-in for Supabase
 * Auth — see prisma/test-support/bootstrap-auth.sql) and returns its id. */
export async function seedAuthUser(isAnonymous = false): Promise<string> {
  const id = randomUUID();
  await prisma.user.create({ data: { id, isAnonymous } });
  return id;
}

/** Seeds an `auth.users` + `profiles` pair with the given role and returns
 * the shared id. */
export async function seedProfile(role: Role, opts: { isAnonymous?: boolean } = {}): Promise<string> {
  const id = await seedAuthUser(opts.isAnonymous ?? false);
  await prisma.profile.create({ data: { id, role } });
  return id;
}

/** Seeds an attraction owned by `ownerId`, defaulting every required
 * non-defaulted column to an arbitrary fixture value — tests only care about
 * `verificationStatus`/`verifiedBy`/`verifiedAt` and don't need realistic
 * listing content. */
export async function seedAttraction(ownerId: string): Promise<string> {
  const attraction = await prisma.attraction.create({
    data: {
      ownerId,
      name: "Fixture Attraction",
      category: "nature",
      address: "123 Fixture St",
      latitude: 10.0,
      longitude: 106.0,
      openingHours: "9am-5pm",
      entryFeeType: "free",
      description: "Seeded by the integration test suite.",
    },
  });
  return attraction.id;
}

/** Seeds a restaurant owned by `ownerId` — same fixture-content rationale as
 * `seedAttraction` above. */
export async function seedRestaurant(ownerId: string): Promise<string> {
  const restaurant = await prisma.restaurant.create({
    data: {
      ownerId,
      name: "Fixture Restaurant",
      priceRange: "$$",
      address: "456 Fixture Ave",
      latitude: 10.0,
      longitude: 106.0,
      phone: "+84000000000",
      openingHours: "9am-9pm",
    },
  });
  return restaurant.id;
}

/** Wipes every table this suite touches between tests, so each test starts
 * from a known-empty state regardless of what earlier tests in the same file
 * (or an earlier run that crashed mid-test) left behind.
 *
 * Deliberately `TRUNCATE`, not a per-table `deleteMany()`/raw `DELETE`: this
 * file is one of the write-guard's allow-listed exceptions specifically
 * because its *inserts* build fixture rows for the guarded write paths to
 * then exercise (see the file-level comment above) — `TRUNCATE` is cleanup
 * infrastructure, not a write path the guard's "did we bypass
 * `updateUserRole`/etc." check cares about, so it intentionally falls
 * outside the guard's `insert|update|delete` keyword scan and needs no
 * allowlist entry of its own.
 *
 * `restart identity cascade`: resets any serial/identity sequences (none
 * currently, but harmless) and follows FKs so truncating `auth.users` also
 * clears `profiles`/`restaurants`/`attractions`/`admin_action_log` rows that
 * reference it, in one statement, regardless of FK ordering. */
export async function resetIntegrationDatabase(): Promise<void> {
  await prisma.$executeRaw`truncate table
    public.admin_action_log,
    public.restaurants,
    public.attractions,
    public.profiles,
    auth.users
    restart identity cascade`;
}
