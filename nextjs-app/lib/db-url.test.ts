import { describe, expect, it } from "vitest";
import { withPgbouncerFlag } from "./db-url";

// Placeholder host and credentials only — nothing here is a real connection.
const POOLER =
  "postgresql://postgres.abcd:secret-pw@aws-0-ap-southeast-1.pooler.supabase.com:6543/postgres";

describe("withPgbouncerFlag — fills in a missing flag on the transaction pooler", () => {
  it("adds ?pgbouncer=true when the URL has no query string", () => {
    expect(withPgbouncerFlag(POOLER)).toEqual({
      url: `${POOLER}?pgbouncer=true`,
      patched: true,
    });
  });

  it("appends with & when other parameters are already present", () => {
    const url = `${POOLER}?sslmode=require&connection_limit=1`;
    expect(withPgbouncerFlag(url)).toEqual({
      url: `${url}&pgbouncer=true`,
      patched: true,
    });
  });

  it("does not double up the separator after a trailing ? or &", () => {
    expect(withPgbouncerFlag(`${POOLER}?`).url).toBe(
      `${POOLER}?pgbouncer=true`,
    );
    expect(withPgbouncerFlag(`${POOLER}?sslmode=require&`).url).toBe(
      `${POOLER}?sslmode=require&pgbouncer=true`,
    );
  });

  it("also handles the postgres:// scheme and IPv6 hosts", () => {
    expect(
      withPgbouncerFlag("postgres://u:pw@pooler.example:6543/db").patched,
    ).toBe(true);
    expect(withPgbouncerFlag("postgresql://u:pw@[::1]:6543/db").patched).toBe(
      true,
    );
  });

  it("trims surrounding whitespace so the flag never lands after a newline", () => {
    expect(withPgbouncerFlag(` ${POOLER}\n`)).toEqual({
      url: `${POOLER}?pgbouncer=true`,
      patched: true,
    });
  });

  it("never re-serialises credentials: the original string is kept byte for byte", () => {
    const tricky =
      "postgresql://postgres.abcd:p%40ss%3Aword%2F%23%25@pooler.example:6543/postgres?sslmode=require";
    const result = withPgbouncerFlag(tricky);
    expect(result.patched).toBe(true);
    expect(result.url).toBe(`${tricky}&pgbouncer=true`);
  });
});

describe("withPgbouncerFlag — leaves everything else untouched", () => {
  it("keeps a URL that already has the flag, wherever it sits", () => {
    for (const url of [
      `${POOLER}?pgbouncer=true`,
      `${POOLER}?sslmode=require&pgbouncer=true`,
      `${POOLER}?pgbouncer=true&connection_limit=1`,
    ]) {
      expect(withPgbouncerFlag(url)).toEqual({ url, patched: false });
    }
  });

  it("respects an explicit pgbouncer=false", () => {
    const url = `${POOLER}?pgbouncer=false`;
    expect(withPgbouncerFlag(url)).toEqual({ url, patched: false });
  });

  it("leaves the session pooler, direct, default-port and local URLs alone", () => {
    for (const url of [
      "postgresql://postgres.abcd:pw@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres",
      "postgresql://postgres:pw@db.abcd.supabase.co/postgres",
      "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
      "postgresql://postgres:postgres@localhost:5432/postgres",
    ]) {
      expect(withPgbouncerFlag(url)).toEqual({ url, patched: false });
    }
  });

  it("ignores non-Postgres schemes even on port 6543", () => {
    for (const url of [
      "mysql://u:pw@host.example:6543/db",
      "https://host.example:6543/path",
    ]) {
      expect(withPgbouncerFlag(url)).toEqual({ url, patched: false });
    }
  });

  it("passes undefined, empty and unparsable values straight through", () => {
    expect(withPgbouncerFlag(undefined)).toEqual({
      url: undefined,
      patched: false,
    });
    expect(withPgbouncerFlag("")).toEqual({ url: "", patched: false });
    expect(withPgbouncerFlag("not a url")).toEqual({
      url: "not a url",
      patched: false,
    });
  });

  it("does not guess when the URL has a fragment", () => {
    const url = `${POOLER}#frag`;
    expect(withPgbouncerFlag(url)).toEqual({ url, patched: false });
  });
});
