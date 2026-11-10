export interface TimelineItem {
  id: string;
  title: string;
  subtitle?: string;
  startLabel: string;
  endLabel?: string;
}

/** Vertical list of date-anchored rows — used for the Upcoming Trips card. */
export function WeekTimeline({ items, emptyLabel = "Nothing scheduled" }: { items: TimelineItem[]; emptyLabel?: string }) {
  if (items.length === 0) {
    return <p className="text-ink/50 text-sm">{emptyLabel}</p>;
  }
  return (
    <ol className="flex flex-col gap-3">
      {items.map((item) => (
        <li key={item.id} className="flex items-center gap-3">
          <div className="flex w-14 shrink-0 flex-col items-center rounded-xl bg-white/5 py-1.5">
            <span className="text-primary text-xs font-semibold uppercase">{item.startLabel}</span>
          </div>
          <div className="min-w-0 flex-1">
            <p className="text-ink truncate text-sm font-medium">{item.title}</p>
            {item.subtitle && <p className="text-ink/50 truncate text-xs">{item.subtitle}</p>}
          </div>
          {item.endLabel && <span className="text-ink/40 text-xs whitespace-nowrap">→ {item.endLabel}</span>}
        </li>
      ))}
    </ol>
  );
}
