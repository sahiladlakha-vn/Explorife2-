"use client";

import { PolarAngleAxis, RadialBar, RadialBarChart } from "recharts";

/** Circular percentage dial — e.g. the Trips in Progress card. */
export function RadialDial({
  percentage,
  color = "#ff6b2b",
  size = 140,
}: {
  percentage: number;
  color?: string;
  size?: number;
}) {
  const clamped = Math.min(100, Math.max(0, percentage));
  const data = [{ value: clamped, fill: color }];

  return (
    <div style={{ width: size, height: size }} className="relative">
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
        <RadialBar background={{ fill: "rgba(255,255,255,0.08)" }} dataKey="value" cornerRadius={10} />
      </RadialBarChart>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="text-ink font-display text-2xl">{Math.round(clamped)}%</span>
      </div>
    </div>
  );
}
