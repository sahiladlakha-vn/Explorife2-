import "server-only";

/**
 * Shared helper for `lib/server/profiles.ts`/`attractions.ts`/`restaurants.ts`:
 * emits a structured server-side warning whenever an unauthorized caller's
 * patch has one or more locked fields silently stripped (role on profiles;
 * verificationStatus/verifiedBy/verifiedAt on attractions/restaurants).
 *
 * The live Postgres triggers did this same strip-and-continue silently and
 * invisibly — there was no log of who attempted it. This doesn't change the
 * behavior (the write still silently succeeds, minus the locked fields), it
 * only makes the attempt observable server-side for auditing/alerting, per
 * the hardening-pass request. Deliberately a plain `console.warn` rather than
 * a new logging dependency — this project has no existing logger to plug
 * into (see `lib/server/write-guard.test.ts` for the broader guard-coverage
 * context this sits alongside).
 */
export function warnStrippedFields(params: {
  userId: string;
  table: "profiles" | "attractions" | "restaurants";
  recordId: string;
  strippedFields: readonly string[];
}): void {
  const { userId, table, recordId, strippedFields } = params;
  if (strippedFields.length === 0) return;
  console.warn(
    `[audit] stripped locked field(s) from an unauthorized write — ` +
      `table=${table} recordId=${recordId} userId=${userId} ` +
      `fields=${strippedFields.join(",")}`,
  );
}
