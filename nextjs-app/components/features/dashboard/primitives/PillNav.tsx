import Link from "next/link";
import { cn } from "@/lib/utils";

export interface PillNavItem {
  label: string;
  /** Omit for nav items that aren't wired to a real route yet — renders as an inert pill instead of a link. */
  href?: string;
}

/**
 * Centered glass pill nav: the active item is a solid white pill. Items
 * without an `href` are screens that don't exist yet and render as visibly
 * disabled (`opacity-50`, `cursor-not-allowed`, "Coming soon" tooltip).
 */
export function PillNav({ items, activeLabel }: { items: PillNavItem[]; activeLabel: string }) {
  return (
    <nav
      aria-label="Admin sections"
      className="glass-card flex max-w-full items-center gap-1 overflow-x-auto rounded-full p-1"
    >
      {items.map((item) => {
        const isActive = item.label === activeLabel;
        const base = "shrink-0 rounded-full px-4 py-2 text-sm font-medium whitespace-nowrap transition-colors";

        if (item.href) {
          return (
            <Link
              key={item.label}
              href={item.href}
              aria-current={isActive ? "page" : undefined}
              className={cn(base, isActive ? "bg-white text-neutral-900" : "text-white/80 hover:text-white")}
            >
              {item.label}
            </Link>
          );
        }
        return (
          <button
            key={item.label}
            type="button"
            aria-disabled="true"
            title="Coming soon"
            className={cn(base, "cursor-not-allowed text-white/80 opacity-50")}
          >
            {item.label}
          </button>
        );
      })}
    </nav>
  );
}
