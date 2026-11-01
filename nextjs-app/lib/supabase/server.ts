import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

/**
 * Server-side Supabase client for use inside Server Components, Server
 * Actions, and Route Handlers — Auth session reads/writes (incl. anonymous
 * sessions + `linkIdentity`) and Storage access only, per the same
 * Prisma-vs-Supabase split documented in lib/supabase/client.ts.
 *
 * Must be created fresh per request (it closes over the request's cookies),
 * so this is a factory, not a singleton like lib/db.ts.
 */
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            );
          } catch {
            // `setAll` is called from a Server Component in some code paths
            // (e.g. rendering inside a cached layout), where cookie writes
            // are a no-op by design — safe to ignore as long as session
            // refresh is also happening in middleware (see
            // lib/supabase/middleware.ts), which is the actual write path.
          }
        },
      },
    },
  );
}
