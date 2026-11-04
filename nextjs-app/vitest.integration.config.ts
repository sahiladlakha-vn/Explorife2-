import { defineConfig } from "vitest/config";
import path from "node:path";

// Config for the real-Postgres integration suite
// (lib/server/integration/*.integration.test.ts) — kept separate from
// vitest.config.ts so the default `npm test`/`vitest run` never picks these
// up (see that file's `exclude` entry). Same aliases as the unit config
// (notably the `server-only` stub, since lib/server/db-as-user.ts and the
// three guarded modules all import it) — everything else about these tests
// is identical to a unit test, the only difference is DATABASE_URL points at
// a real database and `@/lib/db`'s prisma client is never mocked.
//
// Run via `npm run test:integration`, which assumes the environment already
// has DATABASE_URL pointed at a disposable loopback/CI Postgres with
// `prisma/test-support/bootstrap-auth.sql` and
// `prisma/test-support/lock-triggers.sql` applied, and
// `prisma migrate deploy` run against it — see
// .github/workflows/nextjs-ci.yml's `db-trigger-integration` job for the
// canonical sequence.
export default defineConfig({
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "."),
      "server-only": path.resolve(__dirname, "test/stubs/server-only.ts"),
    },
  },
  test: {
    environment: "node",
    include: ["**/*.integration.test.ts"],
    exclude: ["node_modules", ".next", "lib/generated/**"],
    // These tests do real sequential writes/reads against one shared
    // database and reset it between tests (see fixtures.ts's
    // resetIntegrationDatabase) rather than isolating per-worker — run them
    // in a single process/thread to avoid two files racing to truncate the
    // same tables out from under each other.
    fileParallelism: false,
  },
});
