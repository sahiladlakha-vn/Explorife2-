"use client";

import { PolarAngleAxis, RadialBar, RadialBarChart } from "recharts";
import { useMediaQuery } from "@/lib/hooks/use-media-query";

/**
 * Circular percentage dial — the Trips in Progress card. The sweep animation is
 * skipped under reduced motion. (`useMediaQuery`, not framer-motion's
 * `useReducedMotion`, for the hydration-safety reason given on `AnimatedNumber`.)
 */
export function RadialDial({
  percentage,
  color = "#f5c542",
  size = 140,
}: {
  percentage: number;
  color?: string;
  size?: number;
}) {
  const reducedMotion = useMediaQuery("(prefers-reduced-motion: reduce)");
  const clamped = Math.min(100, Math.max(0, percentage));
  const data = [{ value: clamped, fill: color }];

  return (
    <div
      style={{ width: size, height: size }}
      className="relative"
      role="img"
      aria-label={`${Math.round(clamped)} percent`}
    >
      <RadialBarChart
        width={size}
        height={size}
        cx="50%"
        cy="50%"
        innerRadius="72%"
        outerRadius="100%"
        barSize={10}
        data={data}
        startAngle={90}
        endAngle={-270}
      >
        <PolarAngleAxis type="number" domain={[0, 100]} angleAxisId={0} tick={false} />
        <RadialBar
          background={{ fill: "rgba(255,255,255,0.15)" }}
          dataKey="value"
          cornerRadius={10}
          isAnimationActive={!reducedMotion}
        />
      </RadialBarChart>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="text-3xl font-light tracking-tight text-white tabular-nums">{Math.round(clamped)}%</span>
      </div>
    </div>
  );
}
