function SkeletonBlock({ className }: { className?: string }) {
  return <div className={`glass-card animate-pulse rounded-3xl ${className ?? ""}`} />;
}

/** Mirrors `AdminDashboard`'s grid shape so there's no layout shift once the real data streams in. */
export default function AdminDashboardLoading() {
  return (
    <div className="admin-dashboard-backdrop min-h-screen px-4 py-6 md:px-6 lg:px-8">
      <div className="mx-auto flex max-w-7xl flex-col gap-6">
        <SkeletonBlock className="h-14" />

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-[2fr_1fr_1fr_1fr]">
          <SkeletonBlock className="h-36" />
          <SkeletonBlock className="h-36" />
          <SkeletonBlock className="h-36" />
          <SkeletonBlock className="h-36" />
        </div>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <SkeletonBlock className="h-64 lg:col-span-2" />
          <SkeletonBlock className="h-64" />
          <SkeletonBlock className="h-64" />
          <SkeletonBlock className="h-64" />
          <SkeletonBlock className="h-64" />
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
