"use client";

import dynamic from "next/dynamic";

/**
 * `ssr: false` is only allowed in Client Components — this wrapper exists
 * solely so the (async, Server Component) itinerary page can still render
 * the map client-only without itself becoming a Client Component.
 */
const ItineraryMap = dynamic(
  () => import("./ItineraryMap").then((mod) => mod.ItineraryMap),
  { ssr: false },
);

export function ItineraryMapLoader() {
  return <ItineraryMap />;
}
