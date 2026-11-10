"use client";

import { useEffect, useRef, useState, type ComponentType } from "react";
import { cn } from "@/lib/utils";
import type { PublicProfileLookup } from "@/lib/server/trip-setup";
import { findUserByIdentifierAction } from "@/lib/server/trip-setup-actions";
import { BottomSheet } from "./TripCardPrimitives";
import { SearchIcon, InfoCircleIcon, CheckCircleIcon } from "@/components/ui/icons";

/**
 * Ports `traveler_lookup_sheet.dart` in full (367 lines) — search-by-email-
 * or-username sheet for the "+ Add Traveler" button. Unlike the dark `_kPage`
 * "Add X" sheets, this one uses the app's separate warm LIGHT palette
 * (`AppTheme.lightSurface/lightCard/lightBorder/lightInk/lightMute` +
 * `primary`/`primarySoft`) — that's a deliberate, pre-existing split in the
 * Dart source (see globals.css's `light-*` token block), not something this
 * port introduced.
 *
 * `excludeUserIds`/`currentUserId` are both resolved server-side by the
 * caller (`TravelersCard`, from `getTripSetup`'s travelers list and the
 * session user respectively) and passed down as plain props — this app has
 * no client-side auth context/hook to read `AuthProvider.user?.id` from
 * directly, matching every other server-fetch-then-prop-drill boundary in
 * this port.
 */

type LookupState = "idle" | "searching" | "found" | "notFound" | "alreadyAdded" | "isSelf";
type IconComponent = ComponentType<{ className?: string }>;

const DEBOUNCE_MS = 400;

interface TravelerLookupSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  excludeUserIds: Set<string>;
  currentUserId: string;
  onSelect: (profile: PublicProfileLookup) => void;
}

export function TravelerLookupSheet({
  open,
  onOpenChange,
  excludeUserIds,
  currentUserId,
  onSelect,
}: TravelerLookupSheetProps) {
  const [query, setQuery] = useState("");
  const [state, setState] = useState<LookupState>("idle");
  const [result, setResult] = useState<PublicProfileLookup | null>(null);
  const requestSeq = useRef(0);
  const debounceTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Side-effect half of the close-reset: cancel any in-flight debounced
  // search and invalidate its response. Kept in an effect (not the render-time
  // block below) because it touches the external timer/ref, not rendered
  // state — this way the effect itself never calls setState, so it can't
  // trigger a cascading extra render.
  useEffect(() => {
    if (!open) {
      if (debounceTimer.current) clearTimeout(debounceTimer.current);
      requestSeq.current = 0;
    }
  }, [open]);

  // Rendered-state half of the close-reset, mirroring the Dart widget being
  // fully unmounted/remounted by showModalBottomSheet each time it opens —
  // reset so reopening starts fresh. Adjusted directly during render (React's
  // documented pattern for resetting state on a prop transition — react.dev/
  // learn/you-might-not-need-an-effect#adjusting-some-state-when-a-prop-changes)
  // rather than in a useEffect, so closing the sheet doesn't cost an extra
  // post-commit render just to clear these fields.
  const [wasOpen, setWasOpen] = useState(open);
  if (open !== wasOpen) {
    setWasOpen(open);
    if (!open) {
      setQuery("");
      setState("idle");
      setResult(null);
    }
  }

  useEffect(() => {
    return () => {
      if (debounceTimer.current) clearTimeout(debounceTimer.current);
    };
  }, []);

  function handleChange(value: string) {
    setQuery(value);
    if (debounceTimer.current) clearTimeout(debounceTimer.current);
    const trimmed = value.trim();
    if (trimmed === "") {
      setState("idle");
      setResult(null);
      return;
    }
    debounceTimer.current = setTimeout(() => void search(trimmed), DEBOUNCE_MS);
  }

  async function search(trimmed: string) {
    const seq = ++requestSeq.current;
    setState("searching");
    let found: PublicProfileLookup | null;
    try {
      found = await findUserByIdentifierAction(trimmed);
    } catch {
      found = null;
    }
    // A newer keystroke's search may have already landed — drop this stale response.
    if (seq !== requestSeq.current) return;

    setResult(found);
    if (found === null) {
      setState("notFound");
    } else if (found.id === currentUserId) {
      setState("isSelf");
    } else if (excludeUserIds.has(found.id)) {
      setState("alreadyAdded");
    } else {
      setState("found");
    }
  }

  function confirm() {
    if (state !== "found" || result === null) return;
    onSelect(result);
    onOpenChange(false);
  }

  const canAdd = state === "found";

  return (
    <BottomSheet
      open={open}
      onOpenChange={onOpenChange}
      title="Add a traveler"
      contentClassName="bg-light-surface rounded-t-3xl"
      handleClassName="bg-light-border"
    >
      <div className="flex-1 overflow-y-auto px-4 pb-3">
        <p className="text-light-ink mt-3 text-lg font-extrabold">Add a traveler</p>
        <p className="text-light-mute mt-1 text-[12.5px]">Search by email or username.</p>
        <div className="border-light-border bg-light-card focus-within:border-primary focus-within:ring-primary mt-3.5 flex items-center gap-2 rounded-xl border px-3 py-2.5 focus-within:ring-1">
          <SearchIcon className="text-light-mute h-5 w-5 shrink-0" />
          <input
            autoFocus
            type="text"
            value={query}
            onChange={(e) => handleChange(e.target.value)}
            placeholder="Email or username"
            className="text-light-ink placeholder:text-light-mute w-full bg-transparent text-sm focus:outline-none"
          />
        </div>
        <div className="mt-3.5">
          <ResultArea state={state} result={result} onTap={confirm} />
        </div>
      </div>
      <div className="border-light-border bg-light-surface flex shrink-0 items-center gap-3 border-t px-4 py-3">
        <p className="text-light-mute flex-1 text-[12.5px] font-semibold">
          {canAdd ? "Ready to add." : "Search for an email or username above."}
        </p>
        <button
          type="button"
          disabled={!canAdd}
          onClick={confirm}
          className={cn(
            "rounded-xl px-5 py-3 text-sm font-bold",
            canAdd ? "bg-primary text-white" : "bg-light-card text-light-mute",
          )}
        >
          Add
        </button>
      </div>
    </BottomSheet>
  );
}

function ResultArea({
  state,
  result,
  onTap,
}: {
  state: LookupState;
  result: PublicProfileLookup | null;
  onTap: () => void;
}) {
  switch (state) {
    case "idle":
      return null;
    case "searching":
      return (
        <div className="flex justify-center py-4">
          <span
            aria-hidden="true"
            className="border-primary/25 border-t-primary h-5 w-5 animate-spin rounded-full border-2"
          />
        </div>
      );
    case "notFound":
      // Stands in for Icons.person_search_outlined — see components/ui/icons.tsx's file-header note.
      return <InfoMessage icon={SearchIcon} text="No Explorife account found for that email or username." />;
    case "isSelf":
      return <InfoMessage icon={InfoCircleIcon} text="That's you — you're already on this trip as the organizer." />;
    case "alreadyAdded":
      return <InfoMessage icon={CheckCircleIcon} text="Already added to this trip." />;
    case "found":
      return result ? <TravelerResultRow profile={result} onTap={onTap} /> : null;
  }
}

function InfoMessage({ icon: Icon, text }: { icon: IconComponent; text: string }) {
  return (
    <div className="bg-light-card border-light-border flex items-start gap-2.5 rounded-xl border px-3 py-3">
      <Icon className="text-light-mute h-[18px] w-[18px] shrink-0" />
      <p className="text-light-mute text-[12.5px] leading-[1.3]">{text}</p>
    </div>
  );
}

function TravelerResultRow({ profile, onTap }: { profile: PublicProfileLookup; onTap: () => void }) {
  const trimmedName = profile.displayName.trim();
  const initials = trimmedName === "" ? "?" : trimmedName[0]!.toUpperCase();

  return (
    <button
      type="button"
      onClick={onTap}
      className="bg-primary-soft border-primary flex w-full items-center gap-3 rounded-xl border-[1.5px] p-2.5 text-left"
    >
      {profile.avatarUrl ? (
        // eslint-disable-next-line @next/next/no-img-element -- avatar source is arbitrary user-supplied storage URL, not a static/local asset
        <img src={profile.avatarUrl} alt="" className="h-10 w-10 shrink-0 rounded-full object-cover" />
      ) : (
        <div className="bg-primary/12 text-primary flex h-10 w-10 shrink-0 items-center justify-center rounded-full font-bold">
          {initials}
        </div>
      )}
      <div className="min-w-0 flex-1">
        <p className="text-light-ink truncate text-sm font-bold">{profile.displayName}</p>
        {profile.username ? <p className="text-light-mute mt-0.5 text-xs">@{profile.username}</p> : null}
      </div>
      <CheckCircleIcon className="text-primary h-5 w-5 shrink-0" />
    </button>
  );
}
