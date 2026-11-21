"use client";

import { useEffect, useState } from "react";
import { animate } from "framer-motion";
import { formatCompactVnd } from "@/lib/format/vnd";
import { useMediaQuery } from "@/lib/hooks/use-media-query";

export type AnimatedNumberFormat = "integer" | "compact-vnd";

// A string option (not a function) on purpose: Server Components can't pass
// functions to Client Components, so the formatting lives here.
function formatValue(n: number, format?: AnimatedNumberFormat): string {
  if (format === "compact-vnd") return formatCompactVnd(n);
  return n.toLocaleString("en-US");
}

/**
 * Counts up from 0 to `value` on mount. Skips the animation (shows the final
 * value) when the OS prefers reduced motion.
 *
 * The preference comes from the repo's `useMediaQuery`, not framer-motion's
 * `useReducedMotion`: that one reads `matchMedia` during the very first client
 * render, so for a reduced-motion user hydration saw the final number where the
 * server had rendered 0 — a hydration-mismatch error in the console. With
 * `useMediaQuery` the first client render still assumes "no preference" (so it
 * matches the server's 0) and then switches to the real value straight after.
 */
export function AnimatedNumber({
  value,
  format,
  durationSeconds = 1.2,
}: {
  value: number;
  format?: AnimatedNumberFormat;
  durationSeconds?: number;
}) {
  const prefersReducedMotion = useMediaQuery("(prefers-reduced-motion: reduce)");
  const [animatedDisplay, setAnimatedDisplay] = useState(0);

  useEffect(() => {
    if (prefersReducedMotion) return;
    const controls = animate(0, value, {
      duration: durationSeconds,
      ease: "easeOut",
      onUpdate: setAnimatedDisplay,
    });
    return () => controls.stop();
  }, [value, prefersReducedMotion, durationSeconds]);

  const rounded = Math.round(prefersReducedMotion ? value : animatedDisplay);
  return <span>{formatValue(rounded, format)}</span>;
}
