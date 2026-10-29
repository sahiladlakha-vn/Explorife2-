"use client";

import { useState } from "react";
import * as Popover from "@radix-ui/react-popover";
import * as Dialog from "@radix-ui/react-dialog";
import { useSelectedLayoutSegment } from "next/navigation";
import type { Trip } from "@/lib/generated/prisma/client";
import { useMediaQuery } from "@/lib/hooks/use-media-query";
import { formatTripDateRange } from "@/lib/format/trip-dates";
import { ChevronDownIcon } from "@/components/ui/icons";
import { TripList } from "./TripList";

interface TripSwitcherProps {
  trips: Trip[];
  activeTrip: Trip;
}

/**
 * Picks Popover (>=768px) vs. Dialog-as-bottom-sheet (<768px) at render time
 * via `useMediaQuery` rather than CSS, since Popover and Dialog are different
 * Radix primitives (not a single component with responsive styling) and
 * mounting both would double up on focus-trap/outside-click handling.
 */
export function TripSwitcher({ trips, activeTrip }: TripSwitcherProps) {
  const isDesktop = useMediaQuery("(min-width: 768px)");
  const segment = useSelectedLayoutSegment() ?? "trip";
  const [open, setOpen] = useState(false);

  const trigger = (
    <button
      type="button"
      data-testid="trip-switcher-trigger"
      className="hover:bg-surface-raised flex min-w-0 items-center gap-1.5 rounded-md px-2 py-1 text-left transition-colors"
    >
      <span className="min-w-0">
        <span className="text-text flex items-center gap-1 truncate text-base font-semibold">
          <span className="truncate">{activeTrip.name}</span>
          <ChevronDownIcon className="text-text-muted h-4 w-4 shrink-0" />
        </span>
        <span data-testid="trip-date-range" className="text-text-muted block truncate text-xs">
          {formatTripDateRange(activeTrip.startDate, activeTrip.endDate)}
        </span>
      </span>
    </button>
  );

  if (isDesktop) {
    return (
      <Popover.Root open={open} onOpenChange={setOpen}>
        <Popover.Trigger asChild>{trigger}</Popover.Trigger>
        <Popover.Portal>
          <Popover.Content
            data-testid="trip-switcher-popover"
            side="bottom"
            align="start"
            sideOffset={8}
            className="bg-surface border-border z-50 w-80 rounded-lg border shadow-lg"
          >
            <TripList
              trips={trips}
              activeTripId={activeTrip.id}
              segment={segment}
              onNavigate={() => setOpen(false)}
            />
          </Popover.Content>
        </Popover.Portal>
      </Popover.Root>
    );
  }

  return (
    <Dialog.Root open={open} onOpenChange={setOpen}>
      <Dialog.Trigger asChild>{trigger}</Dialog.Trigger>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-50 bg-black/50" />
        <Dialog.Content
          data-testid="trip-switcher-sheet"
          className="bg-surface fixed inset-x-0 bottom-0 z-50 rounded-t-xl pb-[env(safe-area-inset-bottom)] shadow-lg"
        >
          <Dialog.Title className="sr-only">Switch trip</Dialog.Title>
          <div className="border-border mx-auto mt-2 h-1 w-10 rounded-full border-0 bg-current opacity-20" />
          <TripList
            trips={trips}
            activeTripId={activeTrip.id}
            segment={segment}
            onNavigate={() => setOpen(false)}
          />
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
