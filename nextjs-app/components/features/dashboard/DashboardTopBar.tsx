import { Compass } from "lucide-react";
import type { Role } from "@/lib/auth/permissions";
import { PillNav, type PillNavItem } from "./primitives/PillNav";

/**
 * Only "Dashboard" is a real route today — the rest are placeholder pills
 * (no `href`) rendered visibly disabled with a "Coming soon" tooltip. There
 * is deliberately no search box or notification bell until they do something.
 */
const NAV_ITEMS: PillNavItem[] = [
  { label: "Dashboard", href: "/admin/dashboard" },
  { label: "Users" },
  { label: "Trips" },
  { label: "Bookings" },
  { label: "Moderation" },
  { label: "Destinations" },
  { label: "Settings" },
];

/** Mirrors `roleLabel` in components/features/profile/ProfileHeader.tsx — kept file-local like that one rather than shared. */
function roleLabel(role: Role): string {
  return role
    .split("_")
    .map((w) => w[0]!.toUpperCase() + w.slice(1))
    .join(" ");
}

export function DashboardTopBar({ admin }: { admin: { role: Role; name: string | null } }) {
  const initial = (admin.name ?? roleLabel(admin.role)).trim()[0]?.toUpperCase() ?? "A";

  return (
    <header className="grid grid-cols-[1fr_auto] items-center gap-3 md:grid-cols-[1fr_auto_1fr]">
      <div className="flex items-center gap-2">
        <div className="text-dash-accent flex h-9 w-9 items-center justify-center rounded-full bg-white/15">
          <Compass className="h-5 w-5" aria-hidden="true" />
        </div>
        <span className="text-lg font-semibold tracking-tight whitespace-nowrap">ExploriFe Admin</span>
      </div>

      <div className="col-span-2 order-3 flex min-w-0 justify-center md:order-none md:col-span-1">
        <PillNav items={NAV_ITEMS} activeLabel="Dashboard" />
      </div>

      <div className="glass-card flex items-center gap-2 justify-self-end rounded-full py-1 pr-3 pl-1">
        <div className="bg-dash-accent flex h-7 w-7 items-center justify-center rounded-full text-xs font-bold text-neutral-900">
          {initial}
        </div>
        <span className="text-xs font-medium whitespace-nowrap text-white/90">{roleLabel(admin.role)}</span>
      </div>
    </header>
  );
}
