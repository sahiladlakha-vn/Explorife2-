import "server-only";
import { notFound } from "next/navigation";

/**
 * Keeps every `/dev-preview/*` route unreachable outside development and
 * test (e.g. Playwright against a `next start` build) — never in a
 * production deploy, since these routes render fixture data with no auth.
 */
export function assertDevPreviewEnabled(): void {
  if (process.env.NODE_ENV !== "development" && process.env.NODE_ENV !== "test") {
    notFound();
  }
}
