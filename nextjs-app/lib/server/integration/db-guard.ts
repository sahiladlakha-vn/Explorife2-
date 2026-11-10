// Safety guard shared by every `*.integration.test.ts` file. These tests run
// real `INSERT`/`UPDATE`/`DELETE` statements (via the real, unmocked
// `prisma` client from `@/lib/db`) against whatever `DATABASE_URL` resolves
// to, specifically so they can observe the live lock triggers' real
// behavior (see lib/server/db-as-user.ts and README notes in
// prisma/test-support/*.sql). That is exactly the kind of test that must
// never be able to run against the real Supabase project by accident.
//
// Mirrors prisma/seed.ts's `assertSeedIsAllowed()` guard (same two checks,
// same refusal style: a hard, non-override-able throw, no escape-hatch env
// var) rather than inventing a different safety mechanism for this second
// place real writes can happen outside the live project.
const PRODUCTION_PROJECT_REF = "yshgjzmyapdepkapodno";
const ALLOWED_LOOPBACK_HOSTNAMES = new Set(["localhost", "127.0.0.1"]);

export function assertIntegrationTestDatabaseIsSafe() {
  const databaseUrl = process.env.DATABASE_URL;

  if (!databaseUrl) {
    throw new Error("[integration tests] Refusing to run. DATABASE_URL is not set.");
  }

  if (databaseUrl.includes(PRODUCTION_PROJECT_REF)) {
    throw new Error(
      `[integration tests] Refusing to run. DATABASE_URL references the production ` +
        `Supabase project (${PRODUCTION_PROJECT_REF}). These tests may only run ` +
        `against a disposable local/CI Postgres container — see ` +
        `.github/workflows/nextjs-ci.yml's db-trigger-integration job.`,
    );
  }

  let hostname: string;
  try {
    hostname = new URL(databaseUrl).hostname;
  } catch {
    throw new Error(
      `[integration tests] Refusing to run. DATABASE_URL ("${databaseUrl}") isn't a ` +
        `parseable URL.`,
    );
  }

  if (!ALLOWED_LOOPBACK_HOSTNAMES.has(hostname)) {
    throw new Error(
      `[integration tests] Refusing to run. DATABASE_URL's host ("${hostname}") isn't ` +
        `a loopback address. These tests may only run against a disposable ` +
        `local/CI Postgres container, never a hosted database.`,
    );
  }
}
