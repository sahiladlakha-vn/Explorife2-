import type { ReactNode } from "react";

export interface TaskListItem {
  id: string;
  title: string;
  meta: string;
  trailing?: ReactNode;
}

/** Divided list of rows (title + meta + optional trailing content) — used for the Recent Bookings card. */
export function TaskList({ items, emptyLabel = "Nothing here yet" }: { items: TaskListItem[]; emptyLabel?: string }) {
  if (items.length === 0) {
    return <p className="text-ink/50 text-sm">{emptyLabel}</p>;
  }
  return (
    <ul className="flex flex-col divide-y divide-white/5">
      {items.map((item) => (
        <li key={item.id} className="flex items-center justify-between gap-3 py-2.5 first:pt-0 last:pb-0">
          <div className="min-w-0">
            <p className="text-ink truncate text-sm font-medium">{item.title}</p>
            <p className="text-ink/50 text-xs">{item.meta}</p>
          </div>
          {item.trailing && <div className="shrink-0 text-right text-sm">{item.trailing}</div>}
        </li>
      ))}
    </ul>
  );
}
