import Link from "next/link";
import { assertDevPreviewEnabled } from "@/lib/dev-preview/guard";
import { DEV_PREVIEW_TRIPS } from "@/lib/dev-preview/fixtures";

/**
 * Entry point for manually eyeballing the trip header shell with fixture
 * data — the same fixtures Playwright drives in `e2e/trip-header.spec.ts`.
 */
export default function DevPreviewIndexPage() {
  assertDevPreviewEnabled();

  return (
    <div className="flex flex-1 flex-col gap-4 px-6 py-10">
      <h1 className="text-text text-lg font-semibold">Dev preview — trip header fixtures</h1>
      <ul className="flex flex-col gap-2">
        {DEV_PREVIEW_TRIPS.map((trip) => (
          <li key={trip.id}>
            <Link
              href={`/dev-preview/trips/${trip.id}/trip`}
              className="text-accent underline underline-offset-2"
            >
              {trip.name}
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
