"use client";

import { useSyncExternalStore } from "react";

/** Vietnam has a fixed UTC+7 offset — same constant-offset trick as lib/server/admin-dashboard.ts, kept local since this is copy, not data. */
function vietnamGreeting(date: Date): string {
  const vietnamHour = (date.getUTCHours() + 7) % 24;
  if (vietnamHour < 12) return "Good morning";
  if (vietnamHour < 18) return "Good afternoon";
  return "Good evening";
}

const subscribe = () => () => {};
const getServerSnapshot = () => "Welcome";
const getSnapshot = () => vietnamGreeting(new Date());

/**
 * `new Date()` must never run during prerendering (server snapshot is a fixed
 * string) — `useSyncExternalStore` reads the clock only after hydration,
 * client-side, which also sidesteps the `set-state-in-effect` lint rule since
 * there's no effect involved at all.
 */
export function Greeting() {
  const greeting = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
  return <p className="text-ink/60 text-sm">{greeting}</p>;
}
