import { assertDevPreviewEnabled } from "@/lib/dev-preview/guard";

export default function DevPreviewBookingsTabPage() {
  assertDevPreviewEnabled();
  return (
    <div className="px-4 py-6 md:px-6 lg:px-8">
      <p className="text-text-muted text-sm">Bookings tab — dev preview fixture.</p>
    </div>
  );
}
