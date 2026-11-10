"use client";

import { useRef, useState } from "react";
import { cn } from "@/lib/utils";
import type { TripPackingItem } from "@/lib/generated/prisma/client";
import type { TripTraveler } from "@/lib/server/trip-setup";
import {
  addPackingItemAction,
  removePackingItemAction,
  setPackingItemPackedAction,
} from "@/lib/server/trip-setup-actions";
import {
  Card,
  CardHeader,
  EmptyState,
  AddPill,
  TypeChip,
  QuantityStepper,
  TravelerAvatar,
  BottomSheet,
  listCardClassName,
  tripFieldClassName,
} from "./TripCardPrimitives";
import { ChecklistIcon, CloseIcon, CheckCircleIcon, CircleIcon } from "@/components/ui/icons";

/**
 * Ports `_PackingCard`/`_PackingRow`/`_AddPackingItemSheet` (trips_tab.dart:
 * 1201-1508), folding in `_TripSegment`'s own `_CardHeader(icon:
 * checklist_outlined, label: PACKING, color: _kGreen)` (lines 652-653) as
 * this component's header — same reasoning as TravelersCard's/DocumentsCard's
 * header fold-in. `_kGreen` maps to the `--color-success` token added
 * alongside this batch of cards (globals.css) — reused here for the header
 * icon/label, the progress bar's fill, and the packed-row check icon, all
 * four being the same `_kGreen` in the Dart source. `_QuantityStepper`
 * (trips_tab.dart:1510-1551) isn't re-ported in this file — it already lives
 * in TripCardPrimitives.tsx (built for this same card group) and is imported
 * as-is.
 *
 * `TripSetupProvider.addPackingItem`/`removePackingItem` (trip_setup_
 * provider.dart:204-271) are optimistic temp-id-insert / remove-then-
 * rollback — reproduced with plain `useState` + manual splice/replace, same
 * deliberate choice (and same reasoning) as TravelersCard's `addTraveler`
 * and DocumentsCard's `addDocument`/`removeDocument` ports.
 *
 * `togglePacked` (trip_setup_provider.dart:180-200) is new to this card
 * group: an optimistic in-place flip rather than an insert/remove, so its
 * rollback restores the previous `isPacked` value by id, instead of splicing
 * back into a captured index.
 */
export function PackingCard({
  tripId,
  items,
  travelers,
}: {
  tripId: string;
  items: TripPackingItem[];
  travelers: TripTraveler[];
}) {
  const [rows, setRows] = useState(items);
  const [sheetOpen, setSheetOpen] = useState(false);
  const tempSeq = useRef(0);

  const packed = rows.filter((item) => item.isPacked).length;
  const total = rows.length;
  const fill = total === 0 ? 0 : packed / total;

  async function handleAdd(input: {
    assigneeCollaboratorId: string | null;
    label: string;
    category: string | null;
    quantity: number;
  }) {
    const tempId = `temp-${Date.now()}-${tempSeq.current++}`;
    const optimistic: TripPackingItem = {
      id: tempId,
      tripId,
      isPacked: false,
      sortOrder: rows.length,
      ...input,
      createdAt: new Date(),
    };
    setRows((prev) => [...prev, optimistic]);

    try {
      const saved = await addPackingItemAction({ tripId, ...input });
      setRows((prev) => prev.map((item) => (item.id === tempId ? saved : item)));
    } catch {
      setRows((prev) => prev.filter((item) => item.id !== tempId));
    }
  }

  async function handleTogglePacked(itemId: string) {
    const index = rows.findIndex((item) => item.id === itemId);
    if (index === -1) return;
    const wasPacked = rows[index]!.isPacked;
    setRows((prev) => prev.map((item) => (item.id === itemId ? { ...item, isPacked: !wasPacked } : item)));

    try {
      await setPackingItemPackedAction(itemId, !wasPacked);
    } catch {
      setRows((prev) => prev.map((item) => (item.id === itemId ? { ...item, isPacked: wasPacked } : item)));
    }
  }

  async function handleRemove(itemId: string) {
    const index = rows.findIndex((item) => item.id === itemId);
    if (index === -1) return;
    const removed = rows[index]!;
    setRows((prev) => prev.filter((item) => item.id !== itemId));

    try {
      await removePackingItemAction(itemId);
    } catch {
      setRows((prev) => {
        const next = [...prev];
        next.splice(index, 0, removed); // rollback to position
        return next;
      });
    }
  }

  return (
    <div className="flex flex-col gap-2.5">
      <CardHeader icon={ChecklistIcon} label="PACKING" colorClassName="text-success" />
      {total > 0 ? (
        <div>
          <p className="text-text-muted text-xs font-semibold">
            {packed} / {total} packed
          </p>
          <div className="bg-border mt-1.5 h-1.5 overflow-hidden rounded-full">
            <div className="bg-success h-full" style={{ width: `${fill * 100}%` }} />
          </div>
        </div>
      ) : null}
      {rows.length === 0 ? (
        <EmptyState
          icon={ChecklistIcon}
          title="Nothing packed yet"
          subtitle="Add items to build out the packing list."
        />
      ) : (
        <Card className={listCardClassName}>
          {rows.map((item, i) => (
            <PackingRow
              key={item.id}
              item={item}
              travelers={travelers}
              divider={i > 0}
              onTogglePacked={() => handleTogglePacked(item.id)}
              onRemove={() => handleRemove(item.id)}
            />
          ))}
        </Card>
      )}
      <AddPill label="+ Add Item" onClick={() => setSheetOpen(true)} />
      <AddPackingItemSheet open={sheetOpen} onOpenChange={setSheetOpen} travelers={travelers} onSave={handleAdd} />
    </div>
  );
}

function PackingRow({
  item,
  travelers,
  divider,
  onTogglePacked,
  onRemove,
}: {
  item: TripPackingItem;
  travelers: TripTraveler[];
  divider: boolean;
  onTogglePacked: () => void;
  onRemove: () => void;
}) {
  const assignee = item.assigneeCollaboratorId
    ? (travelers.find((t) => t.id === item.assigneeCollaboratorId) ?? null)
    : null;
  const subtitleParts = [item.quantity > 1 ? `×${item.quantity}` : null, item.category ? item.category : null].filter(
    (part): part is string => part !== null,
  );

  return (
    <div className={cn("flex items-center py-2.5", divider && "border-border border-t")}>
      <button
        type="button"
        onClick={onTogglePacked}
        aria-label={item.label}
        aria-pressed={item.isPacked}
        className="flex h-9 w-9 shrink-0 items-center justify-center"
      >
        {item.isPacked ? (
          <CheckCircleIcon className="text-success h-5 w-5" />
        ) : (
          <CircleIcon className="text-text-muted h-5 w-5" />
        )}
      </button>
      <div className="ml-2.5 min-w-0 flex-1">
        <p
          className={cn("truncate text-sm font-bold", item.isPacked ? "text-text-muted line-through" : "text-text")}
        >
          {item.label}
        </p>
        {subtitleParts.length > 0 ? (
          <p className="text-text-muted mt-0.5 text-[11px]">{subtitleParts.join(" · ")}</p>
        ) : null}
      </div>
      {assignee ? (
        <div className="ml-2 shrink-0">
          <TravelerAvatar traveler={assignee} size={26} />
        </div>
      ) : null}
      <button
        type="button"
        onClick={onRemove}
        aria-label="Remove packing item"
        className="flex h-8 w-8 shrink-0 items-center justify-center"
      >
        <CloseIcon className="text-text-muted h-[18px] w-[18px]" />
      </button>
    </div>
  );
}

function AddPackingItemSheet({
  open,
  onOpenChange,
  travelers,
  onSave,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  travelers: TripTraveler[];
  onSave: (input: {
    assigneeCollaboratorId: string | null;
    label: string;
    category: string | null;
    quantity: number;
  }) => void;
}) {
  const [label, setLabel] = useState("");
  const [category, setCategory] = useState("");
  const [quantity, setQuantity] = useState(1);
  const [assigneeCollaboratorId, setAssigneeCollaboratorId] = useState<string | null>(null);

  // Mirrors the Dart widget being fully unmounted/remounted by
  // showModalBottomSheet each time it opens — reset so reopening starts
  // fresh. Adjusted directly during render (React's documented pattern for
  // resetting state on a prop transition — react.dev/learn/you-might-not-
  // need-an-effect#adjusting-some-state-when-a-prop-changes) rather than in
  // a useEffect, so closing the sheet doesn't cost an extra post-commit
  // render just to clear these fields.
  const [wasOpen, setWasOpen] = useState(open);
  if (open !== wasOpen) {
    setWasOpen(open);
    if (!open) {
      setLabel("");
      setCategory("");
      setQuantity(1);
      setAssigneeCollaboratorId(null);
    }
  }

  function adjustQuantity(delta: 1 | -1) {
    setQuantity((prev) => Math.min(Math.max(prev + delta, 1), 99));
  }

  // Fire-and-forget — addPackingItemAction is optimistic and self-rolls-back
  // on error (PackingCard.handleAdd), same convention as this card group's
  // other two "Add X" sheets.
  function handleSave() {
    const trimmedLabel = label.trim();
    if (trimmedLabel === "") return;
    onSave({
      assigneeCollaboratorId,
      label: trimmedLabel,
      category: category.trim() === "" ? null : category.trim(),
      quantity,
    });
    onOpenChange(false);
  }

  return (
    <BottomSheet
      open={open}
      onOpenChange={onOpenChange}
      title="Add packing item"
      contentClassName="bg-bg rounded-t-[28px]"
    >
      <div className="flex-1 overflow-y-auto px-5 pt-4 pb-5">
        <p className="text-text text-lg">Add packing item</p>
        <input
          type="text"
          value={label}
          onChange={(e) => setLabel(e.target.value)}
          placeholder="Item"
          className={cn(tripFieldClassName, "mt-4")}
        />
        <div className="mt-3 flex items-center gap-3">
          <input
            type="text"
            value={category}
            onChange={(e) => setCategory(e.target.value)}
            placeholder="Category (optional)"
            className={cn(tripFieldClassName, "flex-1")}
          />
          <QuantityStepper quantity={quantity} onAdjust={adjustQuantity} />
        </div>
        {travelers.length > 0 ? (
          <div className="mt-3 flex flex-wrap gap-2">
            <TypeChip
              label="Unassigned"
              selected={assigneeCollaboratorId === null}
              onClick={() => setAssigneeCollaboratorId(null)}
            />
            {travelers.map((t) => (
              <TypeChip
                key={t.id}
                label={t.displayName}
                selected={assigneeCollaboratorId === t.id}
                onClick={() => setAssigneeCollaboratorId(t.id)}
              />
            ))}
          </div>
        ) : null}
        <button
          type="button"
          onClick={handleSave}
          className="bg-primary mt-5 w-full rounded-xl py-3.5 text-[15px] font-bold text-white"
        >
          Save
        </button>
      </div>
    </BottomSheet>
  );
}
