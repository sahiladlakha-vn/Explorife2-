import Link from "next/link";
import { cn } from "@/lib/utils";

export interface PillNavItem {
  label: string;
  /** Omit for nav items that aren't wired to a real route yet — renders as an inert pill instead of a link. */
  href?: string;
}

export function PillNav({ items, activeLabel }: { items: PillNavItem[]; activeLabel: string }) {
  return (
    <nav className="bg-glass-surface border-glass-border flex flex-wrap items-center gap-1 rounded-full border p-1">
      {items.map((item) => {
        const isActive = item.label === activeLabel;
        const className = cn(
          "rounded-full px-4 py-2 text-sm font-medium transition-colors",
          isActive ? "bg-primary text-bg" : "text-ink/60 hover:text-ink",
        );
        if (item.href) {
          return (
            <Link key={item.label} href={item.href} className={className}>
              {item.label}
            </Link>
          );
        }
        return (
          <button
            key={item.label}
            type="button"
            className={cn(className, "cursor-not-allowed opacity-50")}
            title="Coming soon"
          >
            {item.label}
          </button>
        );
      })}
    </nav>
  );
}
