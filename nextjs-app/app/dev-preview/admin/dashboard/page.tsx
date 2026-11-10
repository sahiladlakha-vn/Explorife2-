import { assertDevPreviewEnabled } from "@/lib/dev-preview/guard";
import { AdminDashboard } from "@/components/features/dashboard/AdminDashboard";
import { DEV_PREVIEW_ADMIN_DASHBOARD } from "@/lib/dev-preview/admin-dashboard-fixtures";

/**
 * Bypasses auth and the database entirely — unlike
 * `app/dev-preview/protected/page.tsx`'s real-auth flavor, this route feeds
 * fixed fixture data straight into the same `AdminDashboard` component the
 * real `/admin/dashboard` page renders, so the whole dashboard UI can be
 * visually verified without a seeded DB or an admin session.
 */
export default function DevPreviewAdminDashboardPage() {
  assertDevPreviewEnabled();
  return <AdminDashboard data={DEV_PREVIEW_ADMIN_DASHBOARD} />;
}
