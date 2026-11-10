"use client";

import Link from "next/link";
import { useSelectedLayoutSegment } from "next/navigation";
import { cn } from "@/lib/utils";

const TABS = [
  { segment: "overview", label: "Overview", href: "/profile/overview" },
  { segment: "trips", label: "My Trip", href: "/profile/trips" },
  { segment: "saved", label: "Saved Gems", href: "/profile/saved" },
  { segment: "stories", label: "My Stories", href: "/profile/stories" },
  { segment: "badges", label: "Badges", href: "/profile/badges" },
  { segment: "settings", label: "Settings", href: "/profile/settings" },
] as const;

/**
 * Client component purely so `useSelectedLayoutSegment()` can tell which tab
 * is active — `app/profile/layout.tsx` itself doesn't re-render on
 * navigation between its children, so a prop computed once in the layout
 * would go stale the moment the user switches tabs.
 */
export function ProfileTabs() {
  const segment = useSelectedLayoutSegment();

  return (
    <nav className="border-border flex gap-1 overflow-x-auto border-b px-4 md:px-6 lg:px-8">
      {TABS.map((tab) => {
        const isActive = segment === tab.segment;
        return (
          <Link
            key={tab.segment}
            href={tab.href}
            aria-current={isActive ? "page" : undefined}
            className={cn(
              "shrink-0 whitespace-nowrap border-b-2 px-3 py-3 text-sm font-medium transition-colors",
              isActive
                ? "border-accent text-text"
                : "text-text-muted hover:text-text border-transparent",
            )}
          >
            {tab.label}
          </Link>
        );
      })}
    </nav>
  );
}
