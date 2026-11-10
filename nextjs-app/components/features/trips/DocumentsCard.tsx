"use client";

import { useRef, useState } from "react";
import { cn } from "@/lib/utils";
import type { Trip } from "@/lib/generated/prisma/client";
import type { TripDocumentView, TripTraveler } from "@/lib/server/trip-setup";
import { addDocumentAction, removeDocumentAction } from "@/lib/server/trip-setup-actions";
import { DOCUMENT_TYPES, documentTypeLabel, type DocumentType } from "@/lib/trips/document-type";
import { expiryAlertFor, formatDocumentDate } from "@/lib/trips/document-alerts";
import {
  Card,
  CardHeader,
  EmptyState,
  AddPill,
  TypeChip,
  PickerField,
  BottomSheet,
  listCardClassName,
  tripFieldClassName,
} from "./TripCardPrimitives";
import { DocumentIcon, CalendarIcon, CloseIcon } from "@/components/ui/icons";

/**
 * Ports `_DocumentsCard`/`_DocumentRow`/`_AddDocumentSheet`/`_TypeChip`
 * (trips_tab.dart:886-1196), folding in `_TripSegment`'s own
 * `_CardHeader(icon: description_outlined, label: DOCUMENTS, color: _kTeal)`
 * (lines 639-642) as this component's header — same reasoning as
 * TravelersCard's header fold-in. `_expiryAlertFor`/`_fmtDocDate` are ported
 * to lib/trips/document-alerts.ts (unit-tested there) rather than inlined
 * here, mirroring document-type.ts's own split.
 *
 * `TripSetupProvider.addDocument`/`removeDocument` (trip_setup_provider.dart:
 * 275-342) are optimistic temp-id-insert / remove-then-rollback — reproduced
 * with plain `useState` + manual splice/replace, same deliberate choice (and
 * same reasoning) as TravelersCard's `addTraveler` port.
 */
export function DocumentsCard({
  trip,
  documents,
  travelers,
}: {
  trip: Pick<Trip, "id" | "startDate" | "endDate">;
  documents: TripDocumentView[];
  travelers: TripTraveler[];
}) {
  const [rows, setRows] = useState(documents);
  const [sheetOpen, setSheetOpen] = useState(false);
  const tempSeq = useRef(0);

  async function handleAdd(input: {
    type: DocumentType;
    title: string;
    fileUrl: string | null;
    expiresOn: Date | null;
  }) {
    const tempId = `temp-${Date.now()}-${tempSeq.current++}`;
    const optimistic: TripDocumentView = {
      id: tempId,
      tripId: trip.id,
      ownerCollaboratorId: null,
      ...input,
      createdAt: new Date(),
    };
    setRows((prev) => [...prev, optimistic]);

    try {
      const saved = await addDocumentAction({ tripId: trip.id, ...input });
      setRows((prev) => prev.map((d) => (d.id === tempId ? saved : d)));
    } catch {
      setRows((prev) => prev.filter((d) => d.id !== tempId));
    }
  }

  async function handleRemove(documentId: string) {
    const index = rows.findIndex((d) => d.id === documentId);
    if (index === -1) return;
    const removed = rows[index]!;
    setRows((prev) => prev.filter((d) => d.id !== documentId));

    try {
      await removeDocumentAction(documentId);
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
      <CardHeader icon={DocumentIcon} label="DOCUMENTS" colorClassName="text-teal" />
      {rows.length === 0 ? (
        <EmptyState
          icon={DocumentIcon}
          title="No documents yet"
          subtitle="Passports, visas, tickets, and reservations you add will show up here."
        />
      ) : (
        <Card className={listCardClassName}>
          {rows.map((doc, i) => (
            <DocumentRow
              key={doc.id}
              document={doc}
              trip={trip}
              travelers={travelers}
              divider={i > 0}
              onRemove={() => handleRemove(doc.id)}
            />
          ))}
        </Card>
      )}
      <AddPill label="+ Add Document" onClick={() => setSheetOpen(true)} />
      <AddDocumentSheet open={sheetOpen} onOpenChange={setSheetOpen} onSave={handleAdd} />
    </div>
  );
}

function DocumentRow({
  document,
  trip,
  travelers,
  divider,
  onRemove,
}: {
  document: TripDocumentView;
  trip: Pick<Trip, "startDate" | "endDate">;
  travelers: TripTraveler[];
  divider: boolean;
  onRemove: () => void;
}) {
  const alert = expiryAlertFor(document, trip);
  const ownerId = document.ownerCollaboratorId;
  const ownerLabel =
    ownerId === null ? "Shared" : (travelers.find((t) => t.id === ownerId)?.displayName ?? "Traveler");
  const subtitle = `${documentTypeLabel(document.type)} · ${ownerLabel}`;

  return (
    <div className={cn("flex items-start py-3", divider && "border-border border-t")}>
      <div className="min-w-0 flex-1">
        <p className="text-text truncate text-sm font-bold">{document.title}</p>
        <p className="text-text-muted mt-0.5 text-[11px]">{subtitle}</p>
        {document.expiresOn ? (
          <p className="text-text-muted mt-0.5 text-[11px]">Expires {formatDocumentDate(document.expiresOn)}</p>
        ) : null}
        {alert ? (
          <span
            className={cn(
              "mt-1.5 inline-block rounded-full px-2 py-[3px] text-[9.5px] font-bold tracking-[0.6px]",
              alert.tone === "critical" ? "bg-danger/12 text-danger" : "bg-warn/12 text-warn",
            )}
          >
            {alert.label}
          </span>
        ) : null}
      </div>
      <button
        type="button"
        onClick={onRemove}
        aria-label="Remove document"
        className="flex h-8 w-8 shrink-0 items-center justify-center"
      >
        <CloseIcon className="text-text-muted h-[18px] w-[18px]" />
      </button>
    </div>
  );
}

function toDateInputValue(d: Date): string {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function AddDocumentSheet({
  open,
  onOpenChange,
  onSave,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSave: (input: { type: DocumentType; title: string; fileUrl: string | null; expiresOn: Date | null }) => void;
}) {
  const [type, setType] = useState<DocumentType>("passport");
  const [title, setTitle] = useState("");
  const [url, setUrl] = useState("");
  const [expiresOn, setExpiresOn] = useState<Date | null>(null);
  const dateInputRef = useRef<HTMLInputElement>(null);

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
      setType("passport");
      setTitle("");
      setUrl("");
      setExpiresOn(null);
    }
  }

  // There's no Flutter-style native date-picker dialog on the web — the
  // closest equivalent with zero new dependencies is the browser's own
  // `<input type="date">` picker, triggered from the already-styled
  // PickerField button via `showPicker()` so it still looks like every other
  // picker-style field in this app rather than a bare native input.
  function openDatePicker() {
    const el = dateInputRef.current;
    if (!el) return;
    try {
      el.showPicker();
    } catch {
      // Some browsers lack showPicker() or require stricter activation —
      // focusing the (visually hidden but still operable) input at least
      // lets keyboard users open/use its native picker.
      el.focus();
    }
  }

  // Fire-and-forget — addDocumentAction is optimistic and self-rolls-back on
  // error (DocumentsCard.handleAdd), same convention as TravelerLookupSheet's
  // onSelect. No local loading state to manage.
  function handleSave() {
    const trimmedTitle = title.trim();
    if (trimmedTitle === "") return;
    onSave({
      type,
      title: trimmedTitle,
      fileUrl: url.trim() === "" ? null : url.trim(),
      expiresOn,
    });
    onOpenChange(false);
  }

  const now = new Date();
  const minDate = `${now.getFullYear() - 1}-01-01`;
  const maxDate = `${now.getFullYear() + 20}-12-31`;

  return (
    <BottomSheet open={open} onOpenChange={onOpenChange} title="Add document" contentClassName="bg-bg rounded-t-[28px]">
      <div className="flex-1 overflow-y-auto px-5 pt-4 pb-5">
        <p className="text-text text-lg">Add document</p>
        <div className="mt-4 flex flex-wrap gap-2">
          {DOCUMENT_TYPES.map((t) => (
            <TypeChip key={t} label={documentTypeLabel(t)} selected={t === type} onClick={() => setType(t)} />
          ))}
        </div>
        <input
          type="text"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Title"
          className={cn(tripFieldClassName, "mt-3")}
        />
        <div className="relative mt-3">
          <PickerField
            icon={CalendarIcon}
            ariaLabel="Expiry date"
            hasValue={expiresOn !== null}
            text={expiresOn ? formatDocumentDate(expiresOn) : "Expiry date (optional)"}
            onClick={openDatePicker}
          />
          <input
            ref={dateInputRef}
            type="date"
            tabIndex={-1}
            aria-hidden="true"
            min={minDate}
            max={maxDate}
            value={expiresOn ? toDateInputValue(expiresOn) : ""}
            onChange={(e) => setExpiresOn(e.target.value ? new Date(`${e.target.value}T00:00:00.000Z`) : null)}
            className="sr-only"
          />
        </div>
        <input
          type="text"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          placeholder="Link (optional)"
          className={cn(tripFieldClassName, "mt-3")}
        />
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
