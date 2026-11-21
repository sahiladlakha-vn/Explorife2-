// Supabase's transaction pooler (port 6543) can't serve the named prepared
// statements Prisma uses by default. Without `pgbouncer=true` on that URL,
// queries fail intermittently with Postgres `26000 prepared statement "sN"
// does not exist`, `42P05 ... already exists` or `08P01 bind message supplies
// N parameters, but prepared statement ... requires M` — which surfaces as
// the "Something went wrong" screen on signed-in pages. The flag is documented
// in README.md, .env.example and prisma.config.ts; this module is a safety net
// for when the `DATABASE_URL` environment variable is missing it.
//
// It only ever *fills in a missing flag*. Anything else comes back untouched,
// byte for byte: a URL that already has a `pgbouncer` parameter (true or an
// explicit false), a non-Postgres or unparsable string, or any port other than
// 6543 (session pooler, direct, local Postgres). The credentials are never
// re-serialised — the flag is appended to the original string.
export const TRANSACTION_POOLER_PORT = "6543";

export type RuntimeDatabaseUrl = {
  /** The URL to use: the input itself, unless `patched`. */
  url: string | undefined;
  /** True only when `pgbouncer=true` was appended. */
  patched: boolean;
};

export function withPgbouncerFlag(
  rawUrl: string | undefined,
): RuntimeDatabaseUrl {
  const untouched = { url: rawUrl, patched: false };
  if (!rawUrl) return untouched;

  // Env values pasted into a dashboard often carry a trailing newline/space;
  // trim before appending so the flag doesn't land after the whitespace.
  const base = rawUrl.trim();

  let parsed: URL;
  try {
    parsed = new URL(base);
  } catch {
    return untouched;
  }

  if (parsed.protocol !== "postgresql:" && parsed.protocol !== "postgres:") {
    return untouched;
  }
  if (parsed.port !== TRANSACTION_POOLER_PORT) return untouched;
  // Respect an explicit choice either way; only a *missing* flag is filled in.
  if (parsed.searchParams.has("pgbouncer")) return untouched;
  // A fragment would swallow an appended query string; don't guess.
  if (base.includes("#")) return untouched;

  const separator = !base.includes("?") ? "?" : /[?&]$/.test(base) ? "" : "&";
  return { url: `${base}${separator}pgbouncer=true`, patched: true };
}
