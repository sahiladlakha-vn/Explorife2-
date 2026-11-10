// Guards against silently editing an already-applied Prisma migration file.
// See MIGRATION_PLAN.md's "Migration safety rules": "Never edit a migration
// that has been applied to the live DB. If one must change, update its
// stored checksum deliberately, with a recorded reason." This script is the
// mechanical enforcement of that rule in CI — it does NOT touch any
// database (live or otherwise); it only compares the sha256 checksum of
// each prisma/migrations/*/migration.sql file on disk against a committed
// manifest (prisma/migration-checksums.json — kept OUTSIDE prisma/migrations/
// itself, since that directory is Prisma's own and should contain only
// migration folders and migration_lock.toml). A mismatch fails CI unless the
// manifest is updated (via --write) in the same PR — forcing any migration
// edit to be a deliberate, reviewable, two-file diff (migration.sql +
// migration-checksums.json together) instead of a silent one-line change
// nobody notices in review.
//
// This exists because of a real incident: 2026-11-02's `06a2dd4` edited
// `0_init/migration.sql` (fixing two columns that used invalid
// column-referencing `DEFAULT` SQL — see that commit and the file's own
// "REGENERATED 2026-11-02" header comment) *after* `0_init` had already been
// `prisma migrate resolve --applied`'d against the live database. That's a
// legitimate fix (it makes the migration match what the live columns
// actually are), but it silently invalidates the checksum Prisma already
// recorded in the live `_prisma_migrations` table for that migration name —
// `prisma migrate status`/`deploy` against the live DB will now report
// `0_init` as "modified after it was applied" until that row's `checksum`
// column is deliberately updated to match (a metadata-only fix, prepared —
// not run — as part of the same incident). Nothing catches a repeat of this
// locally (typecheck/lint/unit tests mock Prisma or never touch
// `prisma/migrations/`), hence this CI check.
//
// Checksum algorithm: plain SHA-256 hex digest of the file's raw bytes —
// the same primitive Prisma's own schema-engine uses to populate
// `_prisma_migrations.checksum` (confirmed from
// `schema-engine/connectors/schema-connector/src/checksum.rs` in
// github.com/prisma/prisma-engines: `compute_checksum` is
// `Sha256::new().update(script).finalize()`, hex-encoded via
// `format_checksum`). Note this script does NOT replicate the engine's
// line-ending-tolerant *comparison* logic (`script_matches_checksum`, which
// also tries the content with CRLF<->LF normalized before deciding a
// migration is "modified") — it does a strict byte-for-byte comparison,
// which is fine here since the goal is to catch ANY on-disk change to an
// already-recorded migration, not just the subset that would also fail
// Prisma's own (more lenient) check.
//
// Usage:
//   npx tsx scripts/check-migration-checksums.ts          # check (CI mode)
//   npx tsx scripts/check-migration-checksums.ts --write  # regenerate manifest
import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const prismaDir = join(__dirname, "..", "prisma");
const migrationsDir = join(prismaDir, "migrations");
const manifestPath = join(prismaDir, "migration-checksums.json");

function sha256(filePath: string): string {
  return createHash("sha256").update(readFileSync(filePath)).digest("hex");
}

function currentChecksums(): Record<string, string> {
  const entries: Record<string, string> = {};
  for (const name of readdirSync(migrationsDir).sort()) {
    const dir = join(migrationsDir, name);
    if (!statSync(dir).isDirectory()) continue;
    const sqlPath = join(dir, "migration.sql");
    if (!existsSync(sqlPath)) continue;
    entries[name] = sha256(sqlPath);
  }
  return entries;
}

function main() {
  const write = process.argv.includes("--write");
  const current = currentChecksums();

  if (write) {
    writeFileSync(manifestPath, `${JSON.stringify(current, null, 2)}\n`);
    console.log(`Wrote ${manifestPath} with ${Object.keys(current).length} migration(s).`);
    console.log(
      "Make sure your commit message records WHY the migration changed — this " +
        "manifest update is meant to be a deliberate, reviewable act, not routine.",
    );
    return;
  }

  if (!existsSync(manifestPath)) {
    console.error(`Missing ${manifestPath}. Run with --write to create it.`);
    process.exitCode = 1;
    return;
  }

  const manifest: Record<string, string> = JSON.parse(readFileSync(manifestPath, "utf8"));
  const allNames = new Set([...Object.keys(manifest), ...Object.keys(current)]);
  const problems: string[] = [];

  for (const name of allNames) {
    const expected = manifest[name];
    const actual = current[name];
    if (expected === undefined) {
      problems.push(`"${name}" exists on disk but has no entry in migration-checksums.json.`);
    } else if (actual === undefined) {
      problems.push(`"${name}" has a migration-checksums.json entry but migration.sql is missing from disk.`);
    } else if (expected !== actual) {
      problems.push(
        `"${name}" migration.sql has changed:\n` +
          `    expected (manifest): ${expected}\n` +
          `    actual   (on disk):  ${actual}`,
      );
    }
  }

  if (problems.length > 0) {
    console.error("Migration checksum mismatch detected:\n");
    for (const p of problems) console.error(`  - ${p}`);
    console.error(
      "\nAn already-committed Prisma migration's SQL changed without its " +
        "migration-checksums.json entry being updated in the same PR. Per MIGRATION_PLAN.md's " +
        '"Migration safety rules": never edit a migration that has been applied to ' +
        "the live DB without deliberately updating its stored checksum, with a " +
        "recorded reason (both here, and in the live DB's _prisma_migrations table " +
        "— see that file for the exact process). If this change is intentional, run " +
        "`npx tsx scripts/check-migration-checksums.ts --write`, commit the updated " +
        "migration-checksums.json alongside migration.sql, and explain why in the commit message.",
    );
    process.exitCode = 1;
    return;
  }

  console.log(`OK — ${Object.keys(current).length} migration checksum(s) match migration-checksums.json.`);
}

main();
