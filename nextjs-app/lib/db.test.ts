import path from "node:path";
import {
  afterEach,
  beforeEach,
  describe,
  expect,
  it,
  vi,
  type MockInstance,
} from "vitest";

// `vi.mock` is hoisted above the imports, so anything its factory touches has
// to come from `vi.hoisted`. The mock records every client's constructor
// options so the tests can see what lib/db.ts hands to Prisma.
const { clientOptions } = vi.hoisted(() => ({
  clientOptions: [] as unknown[],
}));

vi.mock("./generated/prisma/client", () => ({
  PrismaClient: class {
    constructor(options?: unknown) {
      clientOptions.push(options);
    }
  },
}));

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

describe("lib/db datasource URL", () => {
  // Placeholder host and credentials only — nothing here is a real connection.
  const POOLER =
    "postgresql://postgres.abcd:secret-pw@aws-0-ap-southeast-1.pooler.supabase.com:6543/postgres";
  let savedUrl: string | undefined;
  let warn: MockInstance<typeof console.warn>;

  beforeEach(() => {
    savedUrl = process.env.DATABASE_URL;
    delete process.env.DATABASE_URL;
    clientOptions.length = 0;
    warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    delete (globalThis as { prisma?: unknown }).prisma;
  });

  afterEach(() => {
    if (savedUrl === undefined) delete process.env.DATABASE_URL;
    else process.env.DATABASE_URL = savedUrl;
    warn.mockRestore();
    delete (globalThis as { prisma?: unknown }).prisma;
  });

  it("adds pgbouncer=true to a transaction-pooler URL that lacks it, and warns without leaking the URL", async () => {
    process.env.DATABASE_URL = POOLER;
    await importDb();
    expect(clientOptions).toHaveLength(1);
    expect(clientOptions[0]).toMatchObject({
      datasourceUrl: `${POOLER}?pgbouncer=true`,
    });
    expect(warn).toHaveBeenCalledTimes(1);
    const message = String(warn.mock.calls[0][0]);
    expect(message).toContain("pgbouncer=true");
    expect(message).not.toContain("secret-pw");
    expect(message).not.toContain("pooler.supabase.com");
  });

  it("passes no datasourceUrl (Prisma keeps reading DATABASE_URL itself) when the flag is already there", async () => {
    process.env.DATABASE_URL = `${POOLER}?pgbouncer=true`;
    await importDb();
    expect(clientOptions[0]).not.toHaveProperty("datasourceUrl");
    expect(warn).not.toHaveBeenCalled();
  });

  it("leaves local and session-pooler URLs alone", async () => {
    process.env.DATABASE_URL =
      "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
    await importDb();
    expect(clientOptions[0]).not.toHaveProperty("datasourceUrl");
    expect(warn).not.toHaveBeenCalled();
  });

  it("does nothing when DATABASE_URL is unset (Prisma reports that itself)", async () => {
    await importDb();
    expect(clientOptions[0]).not.toHaveProperty("datasourceUrl");
    expect(warn).not.toHaveBeenCalled();
  });

  it("does not build a second client when one already exists (dev hot reload)", async () => {
    process.env.DATABASE_URL = POOLER;
    (globalThis as { prisma?: unknown }).prisma = {};
    await importDb();
    expect(clientOptions).toHaveLength(0);
    expect(warn).not.toHaveBeenCalled();
  });
});
