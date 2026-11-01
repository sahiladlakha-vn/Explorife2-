"use client";

import { useSyncExternalStore } from "react";

/**
 * SSR-safe `matchMedia` hook — `getServerSnapshot` returns `false` so the
 * server-rendered HTML always matches the mobile/no-match layout, then
 * `useSyncExternalStore` reconciles to the real value on the client without
 * a hydration-mismatch warning (a brief flash on desktop is preferable to a
 * console error on every page load).
 */
export function useMediaQuery(query: string): boolean {
  return useSyncExternalStore(
    (onChange) => {
      const mql = window.matchMedia(query);
      mql.addEventListener("change", onChange);
      return () => mql.removeEventListener("change", onChange);
    },
    () => window.matchMedia(query).matches,
    () => false,
  );
}
