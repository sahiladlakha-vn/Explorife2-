import { assertDevPreviewEnabled } from "@/lib/dev-preview/guard";
import { requireRealUserOrRedirect } from "@/lib/auth/guards";

/**
 * Fixture route for Playwright to exercise `requireRealUserOrRedirect`
 * (lib/auth/guards.ts) end-to-end without needing a real OAuth session or a
 * seeded DB row — same "dev-preview fixture" pattern as
 * `app/dev-preview/trips/[tripId]/*` (see lib/dev-preview/guard.ts).
 * A no-session (or guest-session) visit redirects to
 * `/auth?redirect=%2Fdev-preview%2Fprotected`; a real session renders the id.
 *
 * `instant = false`: `requireRealUserOrRedirect` reads `cookies()` (via
 * `getCurrentUser`) outside `<Suspense>` to decide whether to redirect or
 * render the id — Next 16's instant-navigation validation flags this as
 * "runtime data during prerendering" (docs:
 * https://nextjs.org/docs/messages/blocking-prerender-runtime). The docs'
 * own criterion for choosing `instant = false` over wrapping in Suspense is
 * "the route needs request-time data high in the tree to decide what to
 * render ... so there is no meaningful static shell worth showing first" —
 * exactly this page: its entire body is either a redirect or the auth
 * result, nothing static to show first.
 */
export const instant = false;

export default async function DevPreviewProtectedPage() {
  assertDevPreviewEnabled();

  const user = await requireRealUserOrRedirect("/dev-preview/protected");

  return (
    <div className="flex flex-1 flex-col gap-4 px-6 py-10">
      <h1 className="text-text text-lg font-semibold">Dev preview — protected page</h1>
      <p className="text-text-muted text-sm">Signed in as {user.id}.</p>
    </div>
  );
}
