import { DashboardBackdrop } from "@/components/features/dashboard/DashboardBackdrop";
import { dashboardFont } from "@/components/features/dashboard/fonts";
import { cn } from "@/lib/utils";

function SkeletonBlock({ className }: { className?: string }) {
  return <div className={cn("glass-card animate-pulse rounded-3xl", className)} />;
}

/** Mirrors `AdminDashboard`'s grid shape so there's no layout shift once the real data streams in. */
export default function AdminDashboardLoading() {
  return (
    <div
      role="status"
      aria-label="Loading dashboard"
      className={cn(
        dashboardFont.variable,
        "admin-dashboard font-dash relative isolate min-h-screen px-4 py-6 md:px-6 lg:px-8",
      )}
    >
      <DashboardBackdrop />
      <div className="mx-auto flex max-w-7xl flex-col gap-6">
        <SkeletonBlock className="h-14" />

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3 lg:grid-cols-[2fr_1fr_1fr_1fr]">
          <SkeletonBlock className="h-40 sm:col-span-3 lg:col-span-1" />
          <SkeletonBlock className="h-40" />
          <SkeletonBlock className="h-40" />
          <SkeletonBlock className="h-40" />
        </div>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <SkeletonBlock className="h-64 lg:col-span-2" />
          <SkeletonBlock className="h-64" />
          <SkeletonBlock className="h-64" />
          <SkeletonBlock className="h-64" />
          <SkeletonBlock className="h-64 lg:row-span-2" />
          <SkeletonBlock className="h-64 lg:col-span-2" />
        </div>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <SkeletonBlock className="h-56" />
          <SkeletonBlock className="h-56" />
          <SkeletonBlock className="h-56" />
        </div>
      </div>
    </div>
  );
}
