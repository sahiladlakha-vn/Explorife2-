"use client";

import { cn } from "@/lib/utils";

export interface SegmentToggleOption {
  label: string;
  value: string;
}

/** Controlled pill-group toggle — parent owns `value`/`onChange` (Performance Overview's period, Booking Mix's count/value switch). */
export function SegmentToggle({
  options,
  value,
  onChange,
  label,
  className,
}: {
  options: SegmentToggleOption[];
  value: string;
  onChange: (value: string) => void;
  /** Accessible name for the group. */
  label: string;
  className?: string;
}) {
  return (
    <div
      role="group"
      aria-label={label}
      className={cn("inline-flex items-center rounded-full bg-white/10 p-0.5", className)}
    >
      {options.map((option) => {
        const isActive = option.value === value;
        return (
          <button
            key={option.value}
            type="button"
            aria-pressed={isActive}
            data-value={option.value}
            onClick={() => onChange(option.value)}
            className={cn(
              "rounded-full px-3 py-1 text-xs font-medium transition-colors",
              isActive ? "bg-dash-accent text-neutral-900" : "text-white/80 hover:text-white",
            )}
          >
            {option.label}
          </button>
        );
      })}
    </div>
  );
}
