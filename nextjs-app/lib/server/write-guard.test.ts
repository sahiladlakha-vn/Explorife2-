import { describe, it, expect } from "vitest";
import fs from "node:fs";
import path from "node:path";

/**
 * Enforces MIGRATION_PLAN.md §3a's rule (restated at the top of
 * lib/server/profiles.ts, attractions.ts, and restaurants.ts): the three
 * tables with live `auth.uid()`-dependent trigger protections —
 * `profiles.role`, and `attractions`/`restaurants`' verification fields —
 * must only ever be written through those three modules, since they're the
 * only places that run the matching assert/strip logic from
 * lib/auth/permissions.ts. Everywhere else, a direct write would bypass that
 * logic entirely and silently reintroduce the vulnerability those modules
 * exist to close.
 *
 * This test statically scans the project source for four ways that mistake
 * can happen and fails the suite if it finds any of them:
 *
 *   1. `prisma.<model>.<writeMethod>(...)` — the base case — generalized to
 *      `<anyIdentifier>.<model>.<writeMethod>(...)` so it also catches:
 *        - `tx.profile.update(...)` inside `prisma.$transaction(async (tx) => ...)`
 *        - a renamed/aliased import, e.g. `import { prisma as db } from "@/lib/db"`
 *          then `db.attraction.update(...)`
 *   2. `$executeRaw`/`$executeRawUnsafe` calls whose SQL text both writes
 *      (INSERT/UPDATE/DELETE) and names one of the three tables — these skip
 *      Prisma's query builder entirely, so method-name matching alone can't
 *      see them.
 *   3. A Supabase client's `.from("profiles" | "attractions" | "restaurants")
 *      .insert/update/upsert/delete(...)` chain. This codebase's architecture
 *      reserves `@supabase/ssr` clients for Auth/Storage only — see
 *      lib/supabase/server.ts's own doc comment — so ANY direct table write
 *      through a Supabase client's `.from()` here is out of place regardless
 *      of which key backs that client. Deliberately not trying to detect
 *      "is this specifically the service-role client" syntactically: that's
 *      trivially defeated by renaming, and a request issued without the
 *      target user's own session (service-role or otherwise) has the same
 *      `auth.uid()`-is-NULL problem as Prisma's connection (see
 *      `prisma/db-notes.sql` §2) — so the policy is simply "no direct
 *      Supabase-table writes to these 3 tables from this codebase," full
 *      stop.
 */

const PROJECT_ROOT = path.resolve(__dirname, "..", "..");

const PROTECTED_MODELS = ["profile", "attraction", "restaurant"] as const;
const PROTECTED_TABLES = ["profiles", "attractions", "restaurants"] as const;
const WRITE_METHODS = ["create", "update", "updateMany", "upsert", "delete", "deleteMany"] as const;
const SUPABASE_WRITE_METHODS = ["insert", "update", "upsert", "delete"] as const;

const ALLOWED_RELATIVE_PATHS = new Set([
  "lib/server/profiles.ts",
  "lib/server/attractions.ts",
  "lib/server/restaurants.ts",
]);

const SCAN_DIRS = ["app", "components", "lib", "test"];

const EXCLUDED_DIR_NAMES = new Set(["node_modules", ".next", "generated", "coverage"]);

const SOURCE_FILE_PATTERN = /\.(ts|tsx)$/;

interface Violation {
  file: string;
  kind: "prisma-client" | "raw-sql" | "supabase-client";
  model: string;
  method: string;
  line: number;
}

function lineNumberAt(content: string, index: number): number {
  return content.slice(0, index).split("\n").length;
}

// Doc comments throughout this codebase (e.g. lib/auth/permissions.ts,
// lib/server/profiles.ts) legitimately mention `prisma.profile.update(...)`
// etc. as prose when explaining what calls into a given guard — those aren't
// the unguarded call sites this test is looking for. Blank out `//...` and
// `/*...*/` comments (preserving line breaks/length so reported line numbers
// stay accurate) before scanning, while leaving string/template literals
// alone so real code isn't corrupted — all three detectors below run on this
// comment-stripped-but-string-preserving text, since the raw-SQL and
// Supabase-client detectors specifically need to see inside string/template
// literals (that's where the SQL text / table name lives).
const STRING_OR_COMMENT_PATTERN =
  /"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`|\/\/[^\n]*|\/\*[\s\S]*?\*\//g;

function stripComments(content: string): string {
  return content.replace(STRING_OR_COMMENT_PATTERN, (match) => {
    if (match.startsWith("//") || match.startsWith("/*")) {
      return match.replace(/[^\n]/g, " ");
    }
    return match;
  });
}

// --- 1. Prisma-client (or renamed alias, or a `tx` inside $transaction) ---
//
// `<identifier>.<model>.<writeMethod>(` — not anchored to the literal word
// "prisma", so it also matches `tx.profile.update(...)` and `db.profile.update(...)`.
function findPrismaClientViolations(
  codeOnly: string,
): Array<Pick<Violation, "kind" | "model" | "method" | "line">> {
  const methods = WRITE_METHODS.join("|");
  const found: Array<Pick<Violation, "kind" | "model" | "method" | "line">> = [];
  for (const model of PROTECTED_MODELS) {
    const pattern = new RegExp(
      `[A-Za-z_$][\\w$]*\\s*\\.\\s*${model}\\s*\\.\\s*(${methods})\\s*\\(`,
      "g",
    );
    for (const match of codeOnly.matchAll(pattern)) {
      found.push({
        kind: "prisma-client",
        model,
        method: match[1],
        line: lineNumberAt(codeOnly, match.index ?? 0),
      });
    }
  }
  return found;
}

// --- 2. $executeRaw / $executeRawUnsafe ------------------------------------
//
// Finds each `$executeRaw`/`$executeRawUnsafe` call site, then checks a
// generous window of the text that follows (covers both the tagged-template
// form and the plain-string-argument form, across multiple lines) for a
// write keyword *and* one of the three table names. This is a heuristic, not
// a SQL parser — it can't verify the table name and the write keyword are
// part of the same statement if a file packs multiple unrelated raw queries
// within ~1000 characters of each other, but false positives there just mean
// an extra look, not a missed real violation.
const RAW_SQL_WINDOW = 1000;
const WRITE_KEYWORD_PATTERN = /\b(insert|update|delete)\b/i;

// Caps a lookahead window at the next statement-terminating `;` (if any
// precedes the raw character limit), so two unrelated statements sitting
// close together in the same file (e.g. a read immediately followed by an
// unrelated write a line later) don't get merged into one false match.
function statementWindow(content: string, start: number, maxLength: number): string {
  const limit = start + maxLength;
  const nextSemicolon = content.indexOf(";", start);
  const end = nextSemicolon === -1 ? limit : Math.min(limit, nextSemicolon + 1);
  return content.slice(start, end);
}

function findRawSqlViolations(content: string): Array<Pick<Violation, "kind" | "model" | "method" | "line">> {
  const found: Array<Pick<Violation, "kind" | "model" | "method" | "line">> = [];
  const callPattern = /\$executeRaw(Unsafe)?\s*[(`]/g;
  for (const match of content.matchAll(callPattern)) {
    const start = match.index ?? 0;
    const window = statementWindow(content, start, RAW_SQL_WINDOW);
    const writeMatch = window.match(WRITE_KEYWORD_PATTERN);
    if (!writeMatch) continue;
    for (const table of PROTECTED_TABLES) {
      const tablePattern = new RegExp(`\\b${table}\\b`, "i");
      if (tablePattern.test(window)) {
        found.push({
          kind: "raw-sql",
          model: table,
          method: `$executeRaw${match[1] ?? ""}:${writeMatch[1].toLowerCase()}`,
          line: lineNumberAt(content, start),
        });
      }
    }
  }
  return found;
}

// --- 3. Supabase client `.from(table).write(...)` --------------------------
const SUPABASE_WINDOW = 200;

function findSupabaseClientViolations(
  content: string,
): Array<Pick<Violation, "kind" | "model" | "method" | "line">> {
  const found: Array<Pick<Violation, "kind" | "model" | "method" | "line">> = [];
  const fromPattern = /\.from\(\s*["'`](profiles|attractions|restaurants)["'`]\s*\)/g;
  const writeMethods = SUPABASE_WRITE_METHODS.join("|");
  const writePattern = new RegExp(`\\.\\s*(${writeMethods})\\s*\\(`);
  for (const match of content.matchAll(fromPattern)) {
    const start = match.index ?? 0;
    const window = statementWindow(content, start, SUPABASE_WINDOW);
    const writeMatch = window.match(writePattern);
    if (!writeMatch) continue;
    found.push({
      kind: "supabase-client",
      model: match[1],
      method: writeMatch[1],
      line: lineNumberAt(content, start),
    });
  }
  return found;
}

/** Pure, filesystem-free: scans a single file's already-read content. */
function findViolationsInContent(content: string): Array<Omit<Violation, "file">> {
  const codeOnly = stripComments(content);
  return [
    ...findPrismaClientViolations(codeOnly),
    // Raw-SQL and Supabase-client detection need to see inside string/
    // template literals (that's where the SQL/table name lives), so they run
    // on the comment-stripped-but-string-preserving `codeOnly` too — strings
    // are left untouched by stripComments(), only `//`/`/* */` comments are
    // blanked out.
    ...findRawSqlViolations(codeOnly),
    ...findSupabaseClientViolations(codeOnly),
  ];
}

function walk(dir: string, files: string[] = []): string[] {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (EXCLUDED_DIR_NAMES.has(entry.name)) continue;
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(fullPath, files);
    } else if (SOURCE_FILE_PATTERN.test(entry.name)) {
      files.push(fullPath);
    }
  }
  return files;
}

function scanProject(): Violation[] {
  const violations: Violation[] = [];
  for (const dir of SCAN_DIRS) {
    const absoluteDir = path.join(PROJECT_ROOT, dir);
    if (!fs.existsSync(absoluteDir)) continue;
    for (const file of walk(absoluteDir)) {
      const relativePath = path.relative(PROJECT_ROOT, file).split(path.sep).join("/");
      if (ALLOWED_RELATIVE_PATHS.has(relativePath)) continue;
      // This test file itself intentionally contains the model/method/table
      // names (as plain string literals above, not as real call syntax) to
      // build the patterns it's scanning for — excluding it isn't
      // load-bearing today, but keeps a future refactor of this file from
      // ever flagging itself.
      if (relativePath === "lib/server/write-guard.test.ts") continue;

      const content = fs.readFileSync(file, "utf8");
      for (const v of findViolationsInContent(content)) {
        violations.push({ file: relativePath, ...v });
      }
    }
  }
  return violations;
}

describe("protected-table write guard", () => {
  // Meta-tests: prove the scanner actually detects the things it's supposed
  // to, using in-memory fixtures rather than the real filesystem — without
  // these, a typo in a pattern could make the real scan below pass
  // vacuously (finding zero violations because it's matching nothing, not
  // because there are none).
  it("detects a direct write to a protected model in a fixture snippet", () => {
    const bad = `
      import { prisma } from "@/lib/db";
      export async function sneakyRoleChange(id: string) {
        return prisma.profile.update({ where: { id }, data: { role: "super_admin" } });
      }
    `;
    expect(findViolationsInContent(bad)).toEqual([
      expect.objectContaining({ kind: "prisma-client", model: "profile", method: "update" }),
    ]);
  });

  it("detects a write inside prisma.$transaction's `tx` callback param", () => {
    const bad = `
      import { prisma } from "@/lib/db";
      export async function sneaky(id: string) {
        return prisma.$transaction(async (tx) => {
          await tx.attraction.update({ where: { id }, data: { verificationStatus: "verified" } });
        });
      }
    `;
    expect(findViolationsInContent(bad)).toEqual([
      expect.objectContaining({ kind: "prisma-client", model: "attraction", method: "update" }),
    ]);
  });

  it("detects a write through a renamed/aliased Prisma client import", () => {
    const bad = `
      import { prisma as db } from "@/lib/db";
      export async function sneaky(id: string) {
        return db.restaurant.upsert({ where: { id }, create: {}, update: {} });
      }
    `;
    expect(findViolationsInContent(bad)).toEqual([
      expect.objectContaining({ kind: "prisma-client", model: "restaurant", method: "upsert" }),
    ]);
  });

  it("detects a raw UPDATE against profiles via $executeRaw", () => {
    const bad = `
      import { prisma } from "@/lib/db";
      export async function sneaky(id: string) {
        return prisma.$executeRaw\`UPDATE profiles SET role = 'super_admin' WHERE id = \${id}\`;
      }
    `;
    expect(findViolationsInContent(bad)).toEqual([
      expect.objectContaining({ kind: "raw-sql", model: "profiles" }),
    ]);
  });

  it("detects a raw INSERT against restaurants via $executeRawUnsafe", () => {
    const bad = `
      import { prisma } from "@/lib/db";
      export async function sneaky() {
        return prisma.$executeRawUnsafe(
          "INSERT INTO restaurants (owner_id, name) VALUES ($1, $2)",
          ownerId,
          name,
        );
      }
    `;
    expect(findViolationsInContent(bad)).toEqual([
      expect.objectContaining({ kind: "raw-sql", model: "restaurants" }),
    ]);
  });

  it("does not flag a read-only $executeRaw / unrelated table", () => {
    const fine = `
      import { prisma } from "@/lib/db";
      export async function readStuff() {
        return prisma.$executeRaw\`SELECT * FROM profiles\`;
      }
    `;
    expect(findViolationsInContent(fine)).toEqual([]);
  });

  it("detects a Supabase service-role-style client writing to profiles via .from()", () => {
    const bad = `
      import { createClient } from "@supabase/supabase-js";
      const admin = createClient(url, process.env.SUPABASE_SERVICE_ROLE_KEY!);
      export async function sneaky(id: string) {
        await admin.from("profiles").update({ role: "super_admin" }).eq("id", id);
      }
    `;
    expect(findViolationsInContent(bad)).toEqual([
      expect.objectContaining({ kind: "supabase-client", model: "profiles", method: "update" }),
    ]);
  });

  it("detects a Supabase client inserting into attractions via .from()", () => {
    const bad = `
      await supabase.from('attractions').insert({ name: "x" });
    `;
    expect(findViolationsInContent(bad)).toEqual([
      expect.objectContaining({ kind: "supabase-client", model: "attractions", method: "insert" }),
    ]);
  });

  it("does not flag a Supabase .from() read, or reads/writes to unrelated models/tables", () => {
    const fine = `
      import { prisma } from "@/lib/db";
      export async function readStuff(id: string) {
        await prisma.profile.findUnique({ where: { id } });
        await prisma.trip.update({ where: { id }, data: { title: "x" } });
        await supabase.from("profiles").select("*").eq("id", id);
        await supabase.from("trips").update({ title: "x" }).eq("id", id);
      }
    `;
    expect(findViolationsInContent(fine)).toEqual([]);
  });

  it("finds no direct writes to profiles/attractions/restaurants outside lib/server/{profiles,attractions,restaurants}.ts", () => {
    const violations = scanProject();
    expect(violations).toEqual([]);
  });

  it("the three allowed modules actually exist (so the allowlist isn't silently stale)", () => {
    for (const relativePath of ALLOWED_RELATIVE_PATHS) {
      expect(fs.existsSync(path.join(PROJECT_ROOT, relativePath))).toBe(true);
    }
  });
});
