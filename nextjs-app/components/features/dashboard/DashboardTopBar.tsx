import { Compass } from "lucide-react";
import type { Role } from "@/lib/auth/permissions";
import { PillNav, type PillNavItem } from "./primitives/PillNav";

/**
 * Only "Dashboard" is a real route today — the rest are placeholder pills
 * (no `href`) for screens that don't exist yet. See the placeholders list
 * for the full rundown.
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

export function DashboardTopBar({ admin }: { admin: { role: Role; email: string } }) {
  const initial = admin.email.trim()[0]?.toUpperCase() ?? "?";

  return (
    <div className="flex flex-wrap items-center justify-between gap-4">
      <div className="flex items-center gap-2">
        <div className="bg-primary/15 text-primary flex h-9 w-9 items-center justify-center rounded-full">
          <Compass className="h-5 w-5" aria-hidden="true" />
        </div>
        <span className="font-display text-ink text-lg tracking-wide">ExploriFe Admin</span>
      </div>

      <PillNav items={NAV_ITEMS} activeLabel="Dashboard" />

      <div className="flex items-center gap-2">
        <div className="border-glass-border flex items-center gap-2 rounded-full border py-1 pr-3 pl-1">
          <div className="bg-primary text-bg flex h-7 w-7 items-center justify-center rounded-full text-xs font-semibold">
            {initial}
          </div>
          <span className="text-ink/70 text-xs font-medium whitespace-nowrap">{roleLabel(admin.role)}</span>
        </div>
      </div>
    </div>
  );
}
