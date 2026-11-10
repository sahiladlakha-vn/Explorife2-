"use client";

import { useEffect, useState } from "react";
import { animate, useReducedMotion } from "framer-motion";
import { formatCompactVnd } from "@/lib/format/vnd";

export type AnimatedNumberFormat = "integer" | "compact-vnd";

function formatValue(n: number, format?: AnimatedNumberFormat): string {
  if (format === "compact-vnd") return `${formatCompactVnd(n)} ₫`;
  return n.toLocaleString("en-US");
}

/** Counts up from 0 to `value` on mount. Skips the animation (renders the final value immediately) when the OS prefers reduced motion. */
export function AnimatedNumber({
  value,
  format,
  durationSeconds = 1.2,
}: {
  value: number;
  format?: AnimatedNumberFormat;
  durationSeconds?: number;
}) {
  const prefersReducedMotion = useReducedMotion();
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
