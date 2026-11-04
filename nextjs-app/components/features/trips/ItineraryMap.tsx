"use client";

import { useEffect, useRef, useState } from "react";
import mapboxgl from "mapbox-gl";
import "mapbox-gl/dist/mapbox-gl.css";
import type { Coords, PlottedStopView } from "@/lib/trips/itinerary";

interface ItineraryMapProps {
  stops: PlottedStopView[];
  color: string;
}

/** Ho Chi Minh City centre — same fallback `add_stop_sheet.dart`/`listings_screen.dart` use for a location-less default. */
const FALLBACK_CENTER: [number, number] = [106.7009, 10.7769];
const MAPBOX_TOKEN = process.env.NEXT_PUBLIC_MAPBOX_TOKEN;

function bearingDegrees(a: Coords, b: Coords): number {
  const lat1 = (a.lat * Math.PI) / 180;
  const lat2 = (b.lat * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const y = Math.sin(dLng) * Math.cos(lat2);
  const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLng);
  const theta = Math.atan2(y, x);
  return ((theta * 180) / Math.PI + 360) % 360;
}

/**
 * One arrow per consecutive pair of stops, at the segment midpoint, rotated
 * to point from the first stop toward the second — ported from
 * `trip_route.dart`'s `bearingDegrees`/`routeArrowPoints`.
 */
function routeArrowPoints(points: Coords[]): Array<Coords & { bearing: number }> {
  const arrows: Array<Coords & { bearing: number }> = [];
  for (let i = 0; i < points.length - 1; i++) {
    arrows.push({
      lat: (points[i].lat + points[i + 1].lat) / 2,
      lng: (points[i].lng + points[i + 1].lng) / 2,
      bearing: bearingDegrees(points[i], points[i + 1]),
    });
  }
  return arrows;
}

function pinElement(label: string, color: string): HTMLDivElement {
  const el = document.createElement("div");
  el.className =
    "flex h-7 w-7 items-center justify-center rounded-full border-2 border-white text-xs font-bold text-white shadow-md";
  el.style.backgroundColor = color;
  el.textContent = label;
  return el;
}

function arrowElement(color: string, bearing: number): HTMLDivElement {
  const el = document.createElement("div");
  el.style.width = "14px";
  el.style.height = "14px";
  el.style.transform = `rotate(${bearing}deg)`;
  el.innerHTML = `<svg viewBox="0 0 20 20"><path d="M10 2L17 16H3L10 2Z" fill="${color}" /></svg>`;
  return el;
}

/**
 * Mapbox GL JS day map: one numbered pin per plottable stop (colored by the
 * day's route color), a connecting route line, and direction arrows at each
 * segment's midpoint — ported from `trip_map_dialog.dart`'s pin/arrow
 * layering (built on `trip_route.dart`'s arrow math) and re-themed dark to
 * match this app's single palette (see `globals.css`'s header comment).
 *
 * Deliberately a smaller slice of that dialog's full feature set: no 3D
 * terrain/pitch, lighting presets, or gesture-shield plumbing, since this
 * map sits in a bounded panel beside the day's stop list rather than
 * full-screen behind floating controls. Pin taps only open a lightweight
 * popup — Step 4 is read-only (MIGRATION_PLAN.md §7), so there's no edit
 * sheet to launch.
 */
export function ItineraryMap({ stops, color }: ItineraryMapProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<mapboxgl.Map | null>(null);
  const markersRef = useRef<mapboxgl.Marker[]>([]);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (!MAPBOX_TOKEN || !containerRef.current) return;
    mapboxgl.accessToken = MAPBOX_TOKEN;
    const map = new mapboxgl.Map({
      container: containerRef.current,
      style: "mapbox://styles/mapbox/dark-v11",
      center: FALLBACK_CENTER,
      zoom: 11,
    });
    map.addControl(new mapboxgl.NavigationControl({ showCompass: false }), "top-right");
    // A present-but-invalid token (e.g. a placeholder left in `.env.local`) doesn't
    // throw synchronously — the style fetch fails async and Mapbox reports it via
    // this event instead, so the `!MAPBOX_TOKEN` check alone can't catch it.
    map.on("error", () => setFailed(true));
    mapRef.current = map;
    return () => {
      map.remove();
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    function render() {
      const map = mapRef.current;
      if (!map) return;

      for (const marker of markersRef.current) marker.remove();
      markersRef.current = [];
      if (map.getLayer("itinerary-route-line")) map.removeLayer("itinerary-route-line");
      if (map.getSource("itinerary-route")) map.removeSource("itinerary-route");

      if (stops.length === 0) return;

      for (const stop of stops) {
        const marker = new mapboxgl.Marker({ element: pinElement(stop.mapLabel, color) })
          .setLngLat([stop.coords.lng, stop.coords.lat])
          .setPopup(new mapboxgl.Popup({ offset: 16 }).setText(`${stop.title} · ${stop.timeLabel}`))
          .addTo(map);
        markersRef.current.push(marker);
      }

      if (stops.length > 1) {
        const coords = stops.map((s): [number, number] => [s.coords.lng, s.coords.lat]);
        map.addSource("itinerary-route", {
          type: "geojson",
          data: { type: "Feature", properties: {}, geometry: { type: "LineString", coordinates: coords } },
        });
        map.addLayer({
          id: "itinerary-route-line",
          type: "line",
          source: "itinerary-route",
          layout: { "line-cap": "round", "line-join": "round" },
          paint: { "line-color": color, "line-width": 3 },
        });

        for (const arrow of routeArrowPoints(stops.map((s) => s.coords))) {
          markersRef.current.push(
            new mapboxgl.Marker({ element: arrowElement(color, arrow.bearing) })
              .setLngLat([arrow.lng, arrow.lat])
              .addTo(map),
          );
        }
      }

      const bounds = stops.reduce(
        (b, s) => b.extend([s.coords.lng, s.coords.lat]),
        new mapboxgl.LngLatBounds(),
      );
      map.fitBounds(bounds, { padding: 56, maxZoom: 15, duration: 0 });
    }

    const map = mapRef.current;
    if (!map) return;
    if (map.isStyleLoaded()) render();
    else map.once("load", render);
  }, [stops, color]);

  if (!MAPBOX_TOKEN || failed) {
    return (
      <div
        data-testid="itinerary-map"
        className="bg-surface-raised text-text-muted flex h-64 w-full items-center justify-center rounded-lg text-sm md:h-96"
      >
        {MAPBOX_TOKEN
          ? "Map unavailable — check NEXT_PUBLIC_MAPBOX_TOKEN"
          : "Map unavailable — missing NEXT_PUBLIC_MAPBOX_TOKEN"}
      </div>
    );
  }

  return (
    <div
      ref={containerRef}
      data-testid="itinerary-map"
      className="h-64 w-full overflow-hidden rounded-lg md:h-96"
    />
  );
}
