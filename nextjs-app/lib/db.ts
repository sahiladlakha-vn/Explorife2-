// Imported from the generated client output (prisma/schema.prisma's
// `generator client { output = "../lib/generated/prisma" }`), not from the
// "@prisma/client" package directly — Prisma 6's `prisma-client` generator
// (the one this schema uses) emits a real, project-local client module
// rather than publishing it through the package. "@prisma/client" is still a
// dependency (the generator's runtime needs it), just not what's imported
// here. ./generated/prisma is gitignored and rebuilt by `prisma generate`
// (wired into `postinstall`, see package.json).
import { PrismaClient } from "./generated/prisma/client";

// Standard Next.js/Prisma dev singleton: without this, every hot-reload in
// `next dev` would re-import this module and spin up a brand-new PrismaClient
// (and new connection pool) on top of the old one, eventually exhausting the
// database's connection limit. In production each server instance still gets
// exactly one client, so the global is only strictly needed in dev — but it's
// harmless to keep in both.
//
// This client connects via DATABASE_URL (the pooled/PgBouncer connection —
// see MIGRATION_PLAN.md §0 and §5) with elevated, RLS-bypassing privileges.
// It must never be imported into a Server Action or Route Handler that
// skips the authorization checks in lib/auth/permissions.ts — RLS is not a
// safety net here. See MIGRATION_PLAN.md §3a for what each
// previously-RLS/SECURITY-DEFINER-enforced check now looks like in TypeScript.
const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined;
};

export const prisma =
  globalForPrisma.prisma ??
  new PrismaClient({
    log: process.env.NODE_ENV === "development" ? ["warn", "error"] : ["error"],
  });

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.prisma = prisma;
}
