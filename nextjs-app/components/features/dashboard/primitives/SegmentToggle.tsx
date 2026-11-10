"use client";

import { cn } from "@/lib/utils";

export interface SegmentToggleOption {
  label: string;
  value: string;
}

/** Controlled pill-group toggle — parent owns `value`/`onChange` (e.g. the Booking Mix card's count/value switch). */
export function SegmentToggle({
  options,
  value,
  onChange,
  className,
}: {
  options: SegmentToggleOption[];
  value: string;
  onChange: (value: string) => void;
  className?: string;
}) {
  return (
    <div className={cn("inline-flex items-center rounded-full bg-white/5 p-0.5", className)}>
      {options.map((option) => {
        const isActive = option.value === value;
        return (
          <button
            key={option.value}
            type="button"
            onClick={() => onChange(option.value)}
            className={cn(
              "rounded-full px-3 py-1 text-xs font-medium transition-colors",
              isActive ? "bg-primary text-bg" : "text-ink/60 hover:text-ink",
            )}
          >
            {option.label}
          </button>
        );
      })}
    </div>
  );
}
