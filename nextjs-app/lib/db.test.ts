import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("./generated/prisma/client", () => ({ PrismaClient: class {} }));

const ENGINE_LIBRARY =
  "lib/generated/prisma/libquery_engine-rhel-openssl-3.0.x.so.node";
const ENV_KEYS = ["VERCEL", "PRISMA_QUERY_ENGINE_LIBRARY"] as const;

async function importDb() {
  vi.resetModules();
  await import("./db");
}

describe("lib/db Prisma engine location", () => {
  const saved: Record<string, string | undefined> = {};

  beforeEach(() => {
    for (const key of ENV_KEYS) {
      saved[key] = process.env[key];
      delete process.env[key];
    }
    delete (globalThis as { prisma?: unknown }).prisma;
  });

  afterEach(() => {
    for (const key of ENV_KEYS) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
    delete (globalThis as { prisma?: unknown }).prisma;
  });

  it("points Prisma at the packaged Linux engine on Vercel", async () => {
    process.env.VERCEL = "1";
    await importDb();
    expect(process.env.PRISMA_QUERY_ENGINE_LIBRARY).toBe(
      path.join(process.cwd(), ENGINE_LIBRARY),
    );
  });

  it("leaves Prisma's own engine lookup alone outside Vercel", async () => {
    await importDb();
    expect(process.env.PRISMA_QUERY_ENGINE_LIBRARY).toBeUndefined();
  });

  it("does not override an explicitly configured engine path", async () => {
    process.env.VERCEL = "1";
    process.env.PRISMA_QUERY_ENGINE_LIBRARY = "/custom/engine.so.node";
    await importDb();
    expect(process.env.PRISMA_QUERY_ENGINE_LIBRARY).toBe(
      "/custom/engine.so.node",
    );
  });
});
