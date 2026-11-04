import { Suspense } from "react";
import { HomeCta } from "@/components/features/home/HomeCta";
import { HomeCtaSkeleton } from "@/components/features/home/HomeCtaSkeleton";

/**
 * `/` is the real landing page — it consolidates Flutter's `/home` route
 * (MIGRATION_PLAN.md §1); there's no separate `/home` path in this port.
 *
 * This is a deliberately minimal first pass, not the full HomeScreen port
 * (lib/screens/home/home_screen.dart): no hero banner, search, featured-
 * gems rail, or Explore Ideas rail yet — that data layer (gems/curated
 * collections/tours) doesn't exist in lib/server yet and is its own future
 * step. For now this just welcomes the visitor and routes them into what's
 * already built: `/auth` to sign in, `/profile/overview` either way (its
 * own guest view handles no-session).
 *
 * Static shell, no dynamic data access — the session-dependent CTA lives in
 * `HomeCta`, a separate Server Component wrapped in `<Suspense>`, so this
 * still prerenders under Cache Components. Same split as `AuthPage`.
 */
export default function Home() {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-4 px-6 text-center">
      <h1 className="font-display text-ink text-5xl tracking-wide">
        ExploriFe
      </h1>
      <p className="text-text-muted max-w-md">
        Plan trips, save your favorite gems, and pick up right where you left
        off.
      </p>
      <Suspense fallback={<HomeCtaSkeleton />}>
        <HomeCta />
      </Suspense>
    </div>
  );
}
