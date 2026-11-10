"use client";

import { useRef, useState } from "react";
import { cn } from "@/lib/utils";
import type { TripTraveler, PublicProfileLookup } from "@/lib/server/trip-setup";
import { addTravelerAction } from "@/lib/server/trip-setup-actions";
import { Card, CardHeader, AddPill, TravelerAvatar, listCardClassName } from "./TripCardPrimitives";
import { TravelerLookupSheet } from "./TravelerLookupSheet";
import { GroupsIcon } from "@/components/ui/icons";

/**
 * Ports `_TravelersCard`/`_TravelerRow` (trips_tab.dart:688-798), folding in
 * `_TripSegment`'s own `_CardHeader(icon: groups_outlined, label: TRAVELERS,
 * color: primary)` (lines 632-635) as this component's header. Dart keeps
 * the header and card as separate sibling widgets only because `_TripSegment`
 * interleaves three header+card pairs in one list — this header never
 * renders without this card or vice versa, so folding them into one
 * self-contained component is a 1:1 functional match with a cleaner React
 * boundary (DocumentsCard/PackingCard do the same).
 *
 * `TripSetupProvider.addTraveler` (trip_setup_provider.dart:354-404) does an
 * optimistic temp-id insert, reconciled against the real inserted row (or
 * rolled back to removal on failure) — reproduced here with plain `useState`
 * seeded from the server-fetched `travelers` prop plus manual splice/replace,
 * same manual-reconcile idiom `TravelerLookupSheet`'s own `search()` already
 * uses. Deliberately NOT React's `useOptimistic`: that hook snaps back to its
 * base-state prop the instant the wrapping transition settles, which would
 * make a successfully-added traveler disappear again unless paired with a
 * full `router.refresh()` round-trip — machinery the Dart original never
 * needed, since it only ever reconciles the one row it just touched.
 *
 * Failed adds roll back silently (no toast): `_openLookup`'s `onSelect` in
 * Dart calls `addTraveler` without awaiting or catching, so a thrown error
 * only ever updates the provider's silent `errorFor` state — never surfaced
 * in this segment's UI — before the optimistic row disappears on its own.
 */
export function TravelersCard({
  tripId,
  travelers,
  currentUserId,
}: {
  tripId: string;
  travelers: TripTraveler[];
  currentUserId: string;
}) {
  // `travelers` always has >=1 entry (the organizer, synthesized by
  // getTripSetup if there's no real row yet) and there's no traveler-removal
  // mutator anywhere in this port, so — unlike _TravelersCard's
  // `travelers.isEmpty` branch, a transient loading-gap fallback that has no
  // equivalent in this server-fetch-then-prop-drill architecture — `rows`
  // can never go empty and needs no blank-card fallback.
  const [rows, setRows] = useState(travelers);
  const [sheetOpen, setSheetOpen] = useState(false);
  const tempSeq = useRef(0);

  async function handleSelect(profile: PublicProfileLookup) {
    const tempId = `temp-${Date.now()}-${tempSeq.current++}`;
    const optimistic: TripTraveler = {
      id: tempId,
      userId: profile.id,
      displayName: profile.displayName,
      avatarUrl: profile.avatarUrl,
      role: "member",
      status: "confirmed",
    };
    setRows((prev) => [...prev, optimistic]);

    try {
      const saved = await addTravelerAction({ tripId, userId: profile.id });
      setRows((prev) => prev.map((t) => (t.id === tempId ? saved : t)));
    } catch {
      setRows((prev) => prev.filter((t) => t.id !== tempId));
    }
  }

  return (
    <div className="flex flex-col gap-2.5">
      <CardHeader icon={GroupsIcon} label="TRAVELERS" colorClassName="text-primary" />
      <Card className={listCardClassName}>
        {rows.map((traveler, i) => (
          <TravelerRow key={traveler.id} traveler={traveler} divider={i > 0} />
        ))}
      </Card>
      <AddPill label="+ Add Traveler" onClick={() => setSheetOpen(true)} />
      <TravelerLookupSheet
        open={sheetOpen}
        onOpenChange={setSheetOpen}
        excludeUserIds={new Set(rows.map((t) => t.userId))}
        currentUserId={currentUserId}
        onSelect={handleSelect}
      />
    </div>
  );
}

function TravelerRow({ traveler, divider }: { traveler: TripTraveler; divider: boolean }) {
  const roleLabel = traveler.role === "organizer" ? "Organizer" : "Member";
  const confirmed = traveler.status === "confirmed";

  return (
    <div className={cn("flex items-center py-3", divider && "border-border border-t")}>
      <TravelerAvatar traveler={traveler} />
      <div className="ml-3 min-w-0 flex-1">
        <p className="text-text truncate text-sm font-bold">{traveler.displayName}</p>
        <p className="text-text-muted mt-0.5 text-[11px]">{roleLabel}</p>
      </div>
      <span
        className={cn(
          "ml-2.5 shrink-0 rounded-full px-[9px] py-[5px] text-[9.5px] font-bold tracking-[0.6px]",
          confirmed ? "bg-success/12 text-success" : "bg-warn/12 text-warn",
        )}
      >
        {confirmed ? "CONFIRMED" : "INVITED"}
      </span>
    </div>
  );
}
