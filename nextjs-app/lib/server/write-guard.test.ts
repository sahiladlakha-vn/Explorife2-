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
 * lib/auth/permissions.ts. Everywhere else, a direct
 * `prisma.<model>.update(...)` (or create/upsert/delete/etc.) would bypass
 * that logic entirely and silently reintroduce the vulnerability those
 * modules exist to close.
 *
 * This test statically scans the project source for exactly that mistake and
 * fails the suite if it finds one, so the guarantee holds even if someone
 * adds a new Server Action next year without reading this comment.
 */

const PROJECT_ROOT = path.resolve(__dirname, "..", "..");

const PROTECTED_MODELS = ["profile", "attraction", "restaurant"] as const;
const WRITE_METHODS = ["create", "update", "updateMany", "upsert", "delete", "deleteMany"] as const;

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
  model: string;
  method: string;
  line: number;
}

// One alternation-based regex per model, built from WRITE_METHODS, so a
// single pass over each file's content finds every match with its index
// (needed to report a line number) — e.g. for "profile":
//   /prisma\s*\.\s*profile\s*\.\s*(create|update|updateMany|upsert|delete|deleteMany)\s*\(/g
function buildPattern(model: string): RegExp {
  const methods = WRITE_METHODS.join("|");
  return new RegExp(`prisma\\s*\\.\\s*${model}\\s*\\.\\s*(${methods})\\s*\\(`, "g");
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
// alone so real code isn't corrupted.
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

/** Pure, filesystem-free: scans a single file's already-read content. */
function findViolationsInContent(content: string): Array<Pick<Violation, "model" | "method" | "line">> {
  const codeOnly = stripComments(content);
  const found: Array<Pick<Violation, "model" | "method" | "line">> = [];
  for (const model of PROTECTED_MODELS) {
    const pattern = buildPattern(model);
    for (const match of codeOnly.matchAll(pattern)) {
      found.push({
        model,
        method: match[1],
        line: lineNumberAt(content, match.index ?? 0),
      });
    }
  }
  return found;
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
      // This test file itself intentionally contains the model/method names
      // (as plain string literals above, not as `prisma.<model>.<method>(`
      // call syntax) to build the patterns it's scanning for — excluding it
      // isn't load-bearing today, but keeps a future refactor of this file
      // from ever flagging itself.
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
  // Meta-test: proves the scanner actually detects the thing it's supposed
  // to, using an in-memory fixture rather than the real filesystem — without
  // this, a typo in buildPattern() could make the real scan below pass
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
      expect.objectContaining({ model: "profile", method: "update" }),
    ]);
  });

  it("does not flag reads or writes to unrelated models", () => {
    const fine = `
      import { prisma } from "@/lib/db";
      export async function readStuff(id: string) {
        await prisma.profile.findUnique({ where: { id } });
        await prisma.trip.update({ where: { id }, data: { title: "x" } });
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
