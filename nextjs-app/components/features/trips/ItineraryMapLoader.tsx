"use client";

import dynamic from "next/dynamic";
import type { PlottedStopView } from "@/lib/trips/itinerary";

/**
 * `ssr: false` is only allowed in Client Components — this wrapper exists
 * solely so the (async, Server Component) itinerary page can still render
 * the map client-only without itself becoming a Client Component.
 */
const ItineraryMap = dynamic(
  () => import("./ItineraryMap").then((mod) => mod.ItineraryMap),
  { ssr: false },
);

interface ItineraryMapLoaderProps {
  stops: PlottedStopView[];
  color: string;
}

export function ItineraryMapLoader({ stops, color }: ItineraryMapLoaderProps) {
  return <ItineraryMap stops={stops} color={color} />;
}
