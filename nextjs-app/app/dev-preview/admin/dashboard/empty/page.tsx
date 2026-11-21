import { assertDevPreviewEnabled } from "@/lib/dev-preview/guard";
import { AdminDashboard } from "@/components/features/dashboard/AdminDashboard";
import { DEV_PREVIEW_ADMIN_DASHBOARD_EMPTY } from "@/lib/dev-preview/admin-dashboard-fixtures";

/**
 * The dashboard as a brand-new environment would show it: every query
 * succeeded and there is no data yet, so every card shows its empty state.
 * Fixture only — no auth, no database; 404s outside development/test.
 */
export default function DevPreviewAdminDashboardEmptyPage() {
  assertDevPreviewEnabled();
  return <AdminDashboard data={DEV_PREVIEW_ADMIN_DASHBOARD_EMPTY} />;
}
