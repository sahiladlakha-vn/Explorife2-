/**
 * Pure view-model builder for the Itinerary tab — groups a trip's stops by
 * day and slot, resolves each stop's display fields (title/category/thumb/
 * cost/transit), and picks which stops are plottable on the day map (ported
 * from Flutter's `lib/core/logic/trip_route.dart` + the `_SpotRow`/
 * `_DayBody` logic in `lib/screens/profile/tabs/trips_tab.dart`). Framework-
 * and Prisma-agnostic on purpose — callers map their query results onto the
 * `Itinerary*Input` shapes below (converting `bigint` money fields to
 * `number` first, since Prisma's `BigInt` isn't safe to pass across the RSC
 * boundary) so this module stays trivially unit-testable with plain object
 * literals.
 */

export type Slot = "morning" | "afternoon" | "evening";

export const SLOT_ORDER: readonly Slot[] = ["morning", "afternoon", "evening"];

const SLOT_RANK: Record<Slot, number> = { morning: 0, afternoon: 1, evening: 2 };

export const SLOT_LABEL: Record<Slot, string> = {
  morning: "Morning",
  afternoon: "Afternoon",
  evening: "Evening",
};

export const SLOT_EMOJI: Record<Slot, string> = {
  morning: "🌅",
  afternoon: "☀️",
  evening: "🌙",
};

const SLOT_DEFAULT_TIME: Record<Slot, string> = {
  morning: "08:30",
  afternoon: "12:00",
  evening: "18:00",
};

/**
 * Per-day route color cycle (ported from `trip_route.dart`'s
 * `tripDayColors`) — deliberately excludes the app's primary CTA orange so a
 * day's route/markers never visually collide with primary buttons.
 */
const TRIP_DAY_COLORS = [
  "#2e86ff",
  "#ff9f1c",
  "#9b5de5",
  "#00bfa6",
  "#ff477e",
  "#4caf50",
  "#6c757d",
  "#00b4d8",
] as const;

export function colorForTripDay(day: number): string {
  return TRIP_DAY_COLORS[(day - 1) % TRIP_DAY_COLORS.length];
}

const CATEGORY_EMOJI: Record<string, string> = {
  hiking: "🥾",
  camping: "⛺",
  viewpoint: "📸",
  food: "🍜",
  temple: "⛩️",
  cave: "🗿",
  coastal: "🌊",
  nature: "🌿",
  heritage: "🏛️",
  landmark: "🌄",
};

function displayCategory(category: string | null): string {
  if (!category) return "Unknown";
  return category[0].toUpperCase() + category.slice(1);
}

function gemEmoji(category: string | null): string {
  return (category && CATEGORY_EMOJI[category]) || "📍";
}

/** Keyword match against free-text transit modes, ported from `_transitIcon`. */
export function transitEmoji(mode: string): string {
  const m = mode.toLowerCase();
  if (m.includes("walk")) return "🚶";
  if (m.includes("taxi") || m.includes("car") || m.includes("grab")) return "🚗";
  if (m.includes("bus")) return "🚌";
  if (m.includes("train") || m.includes("rail")) return "🚆";
  if (m.includes("ferry") || m.includes("boat")) return "⛴️";
  if (m.includes("bike") || m.includes("cycle")) return "🚲";
  if (m.includes("flight") || m.includes("plane")) return "✈️";
  return "➡️";
}

export interface Coords {
  lat: number;
  lng: number;
}

/**
 * Handles both `gem_coords` JSON shapes the Flutter `Gem.fromJson` accepts:
 * a `[lng, lat]` tuple, or a `{lat|latitude, lng|longitude}` object.
 */
export function resolveGemCoords(gemCoords: unknown): Coords | null {
  if (Array.isArray(gemCoords)) {
    const [lng, lat] = gemCoords;
    return typeof lat === "number" && typeof lng === "number" ? { lat, lng } : null;
  }
  if (gemCoords && typeof gemCoords === "object") {
    const obj = gemCoords as Record<string, unknown>;
    const lat = obj.lat ?? obj.latitude;
    const lng = obj.lng ?? obj.longitude;
    return typeof lat === "number" && typeof lng === "number" ? { lat, lng } : null;
  }
  return null;
}

export interface ItineraryGemInput {
  gemName: string;
  category: string | null;
  gemCoords: unknown;
  photoUrl: string | null;
  estDurationMin: number | null;
}

export interface ItineraryStopInput {
  id: string;
  day: number;
  slot: string;
  gemId: string | null;
  customPayload: unknown;
  priceVnd: number | null;
  sortOrder: number;
  transitMode: string | null;
  transitLine: string | null;
  transitDurationMin: number | null;
  transitCostVnd: number | null;
  startTime: Date | null;
  notes: string | null;
  gem: ItineraryGemInput | null;
  /** Whether a `TripBooking` row references this stop at all (regardless of its amount). */
  isBooked: boolean;
  /** That booking's `amountVnd`, already converted to `number`, or `null`. */
  bookingAmountVnd: number | null;
}

export interface ItineraryTripInput {
  startDate: Date;
  endDate: Date;
}

export type ThumbKind = "custom" | "missing" | "photo" | "emoji";

export interface TransitView {
  mode: string;
  line: string | null;
  durationMin: number | null;
  costVnd: number | null;
}

export interface ItineraryStopView {
  id: string;
  slot: Slot;
  isCustom: boolean;
  title: string;
  category: string;
  thumbKind: ThumbKind;
  photoUrl: string | null;
  emoji: string | null;
  timeLabel: string;
  durationMin: number | null;
  cost: number | null;
  isBooked: boolean;
  notes: string | null;
  transit: TransitView | null;
  coords: Coords | null;
}

export interface PlottedStopView extends ItineraryStopView {
  coords: Coords;
  mapLabel: string;
}

export interface DayItinerary {
  day: number;
  date: Date;
  color: string;
  slots: Record<Slot, ItineraryStopView[]>;
  plottedStops: PlottedStopView[];
}

function resolveStopCoords(stop: ItineraryStopInput): Coords | null {
  if (stop.gemId) {
    return stop.gem ? resolveGemCoords(stop.gem.gemCoords) : null;
  }
  const payload = stop.customPayload as Record<string, unknown> | null | undefined;
  const lat = payload?.lat;
  const lng = payload?.lng;
  return typeof lat === "number" && typeof lng === "number" ? { lat, lng } : null;
}

function thumbFor(stop: ItineraryStopInput): Pick<ItineraryStopView, "thumbKind" | "photoUrl" | "emoji"> {
  if (!stop.gemId) return { thumbKind: "custom", photoUrl: null, emoji: null };
  if (!stop.gem) return { thumbKind: "missing", photoUrl: null, emoji: null };
  if (stop.gem.photoUrl) return { thumbKind: "photo", photoUrl: stop.gem.photoUrl, emoji: null };
  return { thumbKind: "emoji", photoUrl: null, emoji: gemEmoji(stop.gem.category) };
}

function titleFor(stop: ItineraryStopInput): string {
  if (!stop.gemId) {
    const payload = stop.customPayload as Record<string, unknown> | null | undefined;
    const customTitle = typeof payload?.title === "string" ? payload.title : null;
    return customTitle ?? "Custom stop";
  }
  return stop.gem?.gemName ?? "Gem unavailable";
}

function categoryFor(stop: ItineraryStopInput): string {
  if (!stop.gemId) return "Custom";
  return stop.gem ? displayCategory(stop.gem.category) : "Unavailable";
}

function timeLabelFor(stop: ItineraryStopInput): string {
  if (stop.startTime) {
    const hh = String(stop.startTime.getUTCHours()).padStart(2, "0");
    const mm = String(stop.startTime.getUTCMinutes()).padStart(2, "0");
    return `${hh}:${mm}`;
  }
  return SLOT_DEFAULT_TIME[stop.slot as Slot];
}

function transitFor(stop: ItineraryStopInput): TransitView | null {
  if (!stop.transitMode) return null;
  return {
    mode: stop.transitMode,
    line: stop.transitLine,
    durationMin: stop.transitDurationMin,
    costVnd: stop.transitCostVnd,
  };
}

function toStopView(stop: ItineraryStopInput): ItineraryStopView {
  return {
    id: stop.id,
    slot: stop.slot as Slot,
    isCustom: !stop.gemId,
    title: titleFor(stop),
    category: categoryFor(stop),
    ...thumbFor(stop),
    timeLabel: timeLabelFor(stop),
    durationMin: stop.gemId ? (stop.gem?.estDurationMin ?? null) : null,
    cost: stop.priceVnd ?? stop.bookingAmountVnd,
    isBooked: stop.isBooked,
    notes: stop.notes,
    transit: transitFor(stop),
    coords: resolveStopCoords(stop),
  };
}

/**
 * Groups stops into one entry per day of the trip (`nights + 1` days,
 * matching `Trip.nights` in the Flutter model), each day's stops sorted by
 * slot rank then `sortOrder` — `sortOrder` is scoped per-slot, not globally
 * unique within a day, so a flat sort by `sortOrder` alone would interleave
 * slots incorrectly (confirmed via `TripProvider.stopsForDay`).
 *
 * Map labels are plain sequential integers ("1", "2", ...) per day among
 * plottable stops only, instead of Flutter's day-prefixed "day.index"
 * (e.g. "1.2") — simplified because only one day's stops are ever shown on
 * the map at once here, making the day prefix redundant.
 */
export function buildItinerary(trip: ItineraryTripInput, stops: ItineraryStopInput[]): DayItinerary[] {
  const dayCount = Math.round((trip.endDate.getTime() - trip.startDate.getTime()) / 86_400_000) + 1;
  const days: DayItinerary[] = [];

  for (let day = 1; day <= dayCount; day++) {
    const dayStops = stops
      .filter((s) => s.day === day)
      .sort((a, b) => {
        const slotDiff = SLOT_RANK[a.slot as Slot] - SLOT_RANK[b.slot as Slot];
        return slotDiff !== 0 ? slotDiff : a.sortOrder - b.sortOrder;
      })
      .map(toStopView);

    const slots: Record<Slot, ItineraryStopView[]> = { morning: [], afternoon: [], evening: [] };
    const plottedStops: PlottedStopView[] = [];

    for (const view of dayStops) {
      slots[view.slot].push(view);
      if (view.coords) {
        plottedStops.push({ ...view, coords: view.coords, mapLabel: String(plottedStops.length + 1) });
      }
    }

    days.push({
      day,
      date: new Date(trip.startDate.getTime() + (day - 1) * 86_400_000),
      color: colorForTripDay(day),
      slots,
      plottedStops,
    });
  }

  return days;
}
