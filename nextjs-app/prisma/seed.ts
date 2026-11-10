// Local/dev-only fixture data. Run via `npx prisma db seed` (wired through
// prisma.config.ts -> `tsx prisma/seed.ts`), NEVER as part of any deploy
// script or CI job that could touch the live/production dataset. See
// MIGRATION_PLAN.md §3/§7.
//
// Safety guard: this is a HARD refusal, not an override-able one. There is
// no environment variable that bypasses it. The seed refuses to run unless
// DATABASE_URL resolves to a loopback host (localhost/127.0.0.1) AND does
// not reference the live Supabase project ref, so it cannot seed fixture
// data into the production dataset even by muscle-memory running
// `prisma db seed`. Point DATABASE_URL at a local Supabase CLI stack
// (`supabase start`) to run this. See MIGRATION_PLAN.md §3/§7 and
// README.md's "Local development database" section.
import { PrismaClient } from "../lib/generated/prisma/client";

// The live/production Supabase project ref (yshgjzmyapdepkapodno). Never
// seed against any URL containing this string, regardless of host.
const PRODUCTION_PROJECT_REF = "yshgjzmyapdepkapodno";
const ALLOWED_LOOPBACK_HOSTNAMES = new Set(["localhost", "127.0.0.1"]);

function assertSeedIsAllowed() {
  const databaseUrl = process.env.DATABASE_URL;

  if (!databaseUrl) {
    throw new Error(`[seed] Refusing to run. DATABASE_URL is not set.`);
  }

  if (databaseUrl.includes(PRODUCTION_PROJECT_REF)) {
    throw new Error(
      `[seed] Refusing to run. DATABASE_URL references the production ` +
        `Supabase project (${PRODUCTION_PROJECT_REF}). This seed may only ` +
        `run against a local dev database. See README.md's "Local ` +
        `development database" section for \`supabase start\` setup.`,
    );
  }

  let hostname: string;
  try {
    hostname = new URL(databaseUrl).hostname;
  } catch {
    throw new Error(
      `[seed] Refusing to run. DATABASE_URL could not be parsed as a URL.`,
    );
  }

  if (!ALLOWED_LOOPBACK_HOSTNAMES.has(hostname)) {
    throw new Error(
      `[seed] Refusing to run. DATABASE_URL host (${hostname}) is not ` +
        `localhost/127.0.0.1. This seed may only run against a local dev ` +
        `database started via the Supabase CLI (\`supabase start\`). See ` +
        `README.md's "Local development database" section.`,
    );
  }

  console.log(`[seed] Target database host: ${hostname} (local, OK)`);
}

const prisma = new PrismaClient();

async function main() {
  assertSeedIsAllowed();

  // Placeholder fixture data only — Step 3 (Database) just establishes the
  // schema; no real Server Actions or routes consume this yet (that starts
  // in Step 4+). Extend this as domain features land, keeping every write
  // idempotent (upsert, not create) so re-running the seed is always safe.
  //
  // IMPORTANT: almost every user-owned table (Profile, Trip, SavedGem, ...)
  // has a mandatory FK to `auth.users`, which Prisma does not own and
  // cannot insert into — `auth.users` rows can only be created through
  // Supabase Auth itself (sign-up, or the Admin API's
  // `supabase.auth.admin.createUser` with the service-role key, per
  // lib/server/admin/users.ts). Seeding user-owned fixture rows therefore
  // requires creating a real test Auth user first via that Admin API, then
  // using its id here — intentionally NOT done in this placeholder seed to
  // avoid silently depending on Auth state. What follows only touches
  // tables with no FK to auth.users, so it's safe to run standalone.
  await prisma.curatedCollection.upsert({
    where: { id: "00000000-0000-0000-0000-0000000000c1" },
    update: {},
    create: {
      id: "00000000-0000-0000-0000-0000000000c1",
      title: "Seed Collection — Hanoi Old Quarter",
      subtitle: "Placeholder fixture row from prisma/seed.ts",
      scopeValue: "hanoi",
    },
  });

  await prisma.tour.upsert({
    where: { id: "00000000-0000-0000-0000-0000000000a1" },
    update: {},
    create: {
      id: "00000000-0000-0000-0000-0000000000a1",
      name: "Seed Tour — Old Quarter Walking Tour",
      category: "city_walk",
    },
  });

  console.log("[seed] Done.");
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
