import { defineConfig } from "vitest/config";
import path from "node:path";

// Minimal unit-test config — no DOM/React component testing yet (that would
// need an `environment: "jsdom"` + `@vitejs/plugin-react` setup), just plain
// Node-environment unit tests for lib/ logic (starting with
// lib/auth/permissions.ts's authorization predicates — see
// MIGRATION_PLAN.md §3a). The `@/*` alias mirrors tsconfig.json's `paths` so
// test files can import the same way app code does.
export default defineConfig({
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "."),
      // See test/stubs/server-only.ts for why this is stubbed out.
      "server-only": path.resolve(__dirname, "test/stubs/server-only.ts"),
    },
  },
  test: {
    environment: "node",
    include: ["**/*.test.ts"],
    // `*.integration.test.ts` files (lib/server/integration/) run real writes
    // against a real Postgres with the live trigger SQL installed — they
    // have their own config (vitest.integration.config.ts) and npm script
    // (`test:integration`) and must never be picked up by the default
    // `vitest run`/`npm test`, which has no database available and whose
    // placeholder DATABASE_URL would fail assertIntegrationTestDatabaseIsSafe()
    // anyway.
    exclude: ["node_modules", ".next", "lib/generated/**", "**/*.integration.test.ts"],
  },
});
