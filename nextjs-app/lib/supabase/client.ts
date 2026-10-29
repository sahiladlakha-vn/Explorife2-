import { createBrowserClient } from "@supabase/ssr";

/**
 * Browser-side Supabase client — Auth (incl. anonymous sign-in +
 * `linkIdentity` for guest-to-real-account upgrade, MIGRATION_PLAN.md
 * Risk #8) and Storage (`gem-photos` / `trip-covers` buckets, Risk #7) only.
 *
 * Never used for data reads/writes: those go through Prisma (lib/db.ts) in
 * Server Components/Actions/Route Handlers, per MIGRATION_PLAN.md §0 — this
 * client's session is irrelevant to Prisma's connection, so PostgREST/RLS
 * never enters the picture on the data side.
 */
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
