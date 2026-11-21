import { assertDevPreviewEnabled } from "@/lib/dev-preview/guard";
import { AdminDashboard } from "@/components/features/dashboard/AdminDashboard";
import { DEV_PREVIEW_ADMIN_DASHBOARD_ERRORS } from "@/lib/dev-preview/admin-dashboard-fixtures";

/**
 * Partial failure: several queries "failed" while the rest loaded, to show
 * that each failing card gets its own error state and nothing else is
 * affected. Fixture only — no auth, no database; 404s outside development/test.
 */
export default function DevPreviewAdminDashboardErrorsPage() {
  assertDevPreviewEnabled();
  return <AdminDashboard data={DEV_PREVIEW_ADMIN_DASHBOARD_ERRORS} />;
}
