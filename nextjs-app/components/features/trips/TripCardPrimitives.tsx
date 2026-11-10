"use client";

import type { ComponentType, ReactNode } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { cn } from "@/lib/utils";
import { MinusIcon, PlusIcon } from "@/components/ui/icons";

/**
 * Shared presentational/interactive atoms for the Trip screen's Travelers/
 * Documents/Packing cards and their "Add X" bottom sheets — ports
 * profile_atoms.dart's `_Card`/`_CardHeader`/`_EmptyState` plus
 * trips_tab.dart's `_AddPill`/`_PickerField`/`_TypeChip`/`_QuantityStepper`
 * (lines 234-343, 1161-1196, 1510-1551) and the `DraggableScrollableSheet` +
 * rounded-top-container shell every "Add X" sheet wraps itself in.
 *
 * Colors deliberately reuse this port's existing generic dark-theme semantic
 * tokens (`bg-surface-raised`, `border-border`, `text-text`, `text-text-muted`)
 * rather than introducing a byte-exact second "profile dark palette" matching
 * profile_palette.dart's `_kCard`/`_kBorder`/`_kInk`/`_kMute` hex values —
 * every already-built Profile/Trip component (ProfileHeader, TripHeader,
 * the Dashboard stat tiles) already made that same call, and a pixel-exact
 * second palette would visually clash against those sibling components on
 * the same page rather than match them. `--color-success` (profile_palette's
 * `_kGreen`, #3C9A5F) is the one genuinely new addition — no existing token
 * covers it (`--color-teal` is a distinct hue used for different semantics).
 */

type IconComponent = ComponentType<{ className?: string }>;

export function Card({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cn("bg-surface-raised border-border w-full rounded-2xl border p-[18px]", className)}>
      {children}
    </div>
  );
}

/** `_Card`'s `vertical: 6` override, used by every list-of-rows card (Travelers/Documents/Packing) — rows provide their own vertical-only padding, so there's no horizontal inset at all between row content and the card's rounded edges. */
export const listCardClassName = "p-0 py-1.5";

export function CardHeader({
  icon: Icon,
  label,
  colorClassName,
}: {
  icon: IconComponent;
  label: string;
  colorClassName: string;
}) {
  return (
    <div className={cn("flex items-center gap-2", colorClassName)}>
      <Icon className="h-[18px] w-[18px]" />
      <span className="text-[13px] font-bold tracking-[1.5px]">{label}</span>
    </div>
  );
}

export function EmptyState({
  icon: Icon,
  title,
  subtitle,
  cta,
  onCtaClick,
}: {
  icon: IconComponent;
  title: string;
  subtitle: string;
  cta?: string;
  onCtaClick?: () => void;
}) {
  return (
    <div className="flex flex-col items-center justify-center p-10 text-center">
      <Icon className="text-border h-14 w-14" />
      <p className="text-text mt-4 text-[26px]">{title}</p>
      <p className="text-text-muted mt-1.5 text-sm leading-[1.5]">{subtitle}</p>
      {cta ? (
        <button
          type="button"
          onClick={onCtaClick}
          className="bg-primary mt-5 rounded-xl px-5 py-3 text-sm font-bold text-white"
        >
          {cta}
        </button>
      ) : null}
    </div>
  );
}

export function AddPill({
  label,
  onClick,
  loading = false,
}: {
  label: string;
  onClick: () => void;
  loading?: boolean;
}) {
  return (
    <button
      type="button"
      disabled={loading}
      onClick={onClick}
      aria-label={label}
      className="border-border text-text-muted w-full rounded-[10px] border py-[11px] text-center text-[12.5px] font-semibold disabled:cursor-not-allowed"
    >
      {loading ? (
        <span
          aria-hidden="true"
          className="border-current/25 border-t-current mx-auto block h-4 w-4 animate-spin rounded-full border-2"
        />
      ) : (
        label
      )}
    </button>
  );
}

export function PickerField({
  icon: Icon,
  text,
  hasValue,
  onClick,
  ariaLabel,
}: {
  icon: IconComponent;
  text: string;
  hasValue: boolean;
  onClick: () => void;
  ariaLabel: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={ariaLabel}
      className="bg-surface-raised border-border flex w-full items-center gap-2.5 rounded-xl border px-3.5 py-3.5 text-left"
    >
      <Icon className="text-text-muted h-[18px] w-[18px] shrink-0" />
      <span className={cn("truncate text-sm", hasValue ? "text-text" : "text-text-muted")}>{text}</span>
    </button>
  );
}

export function TypeChip({ label, selected, onClick }: { label: string; selected: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      aria-pressed={selected}
      onClick={onClick}
      className={cn(
        "rounded-full border px-3.5 py-[9px] text-[12.5px] font-semibold whitespace-nowrap",
        selected ? "bg-primary border-primary text-white" : "bg-surface-raised border-border text-text-muted",
      )}
    >
      {label}
    </button>
  );
}

export function QuantityStepper({
  quantity,
  onAdjust,
}: {
  quantity: number;
  onAdjust: (delta: 1 | -1) => void;
}) {
  return (
    <div className="bg-surface-raised border-border flex shrink-0 items-center rounded-xl border px-1">
      <button
        type="button"
        aria-label="Decrease quantity"
        onClick={() => onAdjust(-1)}
        className="flex h-8 w-8 items-center justify-center"
      >
        <MinusIcon className="text-text-muted h-4 w-4" />
      </button>
      <span className="text-text w-5 text-center text-sm font-bold">{quantity}</span>
      <button
        type="button"
        aria-label="Increase quantity"
        onClick={() => onAdjust(1)}
        className="flex h-8 w-8 items-center justify-center"
      >
        <PlusIcon className="text-text-muted h-4 w-4" />
      </button>
    </div>
  );
}

interface AvatarTraveler {
  displayName: string;
  avatarUrl: string | null;
}

/** Ports `_TravelerAvatar` (trips_tab.dart:806-837) — circular image, or initials-on-tint when there's no `avatarUrl`. */
export function TravelerAvatar({ traveler, size = 36 }: { traveler: AvatarTraveler; size?: number }) {
  const trimmedName = traveler.displayName.trim();
  const initials = trimmedName === "" ? "?" : trimmedName[0]!.toUpperCase();

  if (traveler.avatarUrl) {
    return (
      // eslint-disable-next-line @next/next/no-img-element -- avatar source is arbitrary user-supplied storage URL, not a static/local asset
      <img
        src={traveler.avatarUrl}
        alt=""
        className="shrink-0 rounded-full object-cover"
        style={{ width: size, height: size }}
      />
    );
  }

  return (
    <div
      className="bg-primary/12 text-primary flex shrink-0 items-center justify-center rounded-full font-bold"
      style={{ width: size, height: size, fontSize: size * 0.39 }}
    >
      {initials}
    </div>
  );
}

/** Shared `_lightFieldDecoration` (trips_tab.dart:2533) equivalent — despite the Dart name, it's the dark palette; every "Add X" sheet's TextFields use it. */
export const tripFieldClassName =
  "bg-surface-raised border-border text-text placeholder:text-text-muted focus:border-primary w-full rounded-xl border px-3.5 py-3.5 text-sm focus:outline-none";

/**
 * Generic bottom-sheet shell (Radix Dialog, always rendered as a bottom
 * sheet regardless of viewport — matching `DraggableScrollableSheet`'s use
 * on every viewport in the Dart app, unlike `TripSwitcher`'s responsive
 * Popover/Dialog split). The drag-to-resize gesture itself isn't replicated
 * (same simplification `TripSwitcher`'s own sheet already makes for its
 * handle bar) — a fixed `max-h-[85vh]` with internal scroll covers the same
 * functional need. `contentClassName` supplies the sheet's own background +
 * top radius (dark `_kPage`/28px vs. the light lookup sheet's `lightSurface`/
 * 24px) since those two palettes aren't visually interchangeable.
 */
export function BottomSheet({
  open,
  onOpenChange,
  title,
  contentClassName,
  handleClassName = "bg-border",
  children,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  contentClassName?: string;
  handleClassName?: string;
  children: ReactNode;
}) {
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-50 bg-black/50" />
        <Dialog.Content
          className={cn(
            "fixed inset-x-0 bottom-0 z-50 flex max-h-[85vh] flex-col pb-[env(safe-area-inset-bottom)] focus:outline-none",
            contentClassName,
          )}
        >
          <Dialog.Title className="sr-only">{title}</Dialog.Title>
          <div className={cn("mx-auto mt-2.5 h-[5px] w-11 shrink-0 rounded-full", handleClassName)} />
          {children}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
