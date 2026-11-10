"use client";

import { Bar, BarChart, ResponsiveContainer, Tooltip, XAxis } from "recharts";
import { formatCompactVnd } from "@/lib/format/vnd";

export interface BarMiniDatum {
  label: string;
  value: number;
}

export type BarMiniValueFormat = "raw" | "compact-vnd";

function formatValue(n: number, format?: BarMiniValueFormat): number | string {
  if (format === "compact-vnd") return `${formatCompactVnd(n)} ₫`;
  return n;
}

/** Small sparkline-style bar chart — e.g. the Booking Value card's 7-day series. */
export function BarMini({
  data,
  color = "#ff6b2b",
  valueFormat,
}: {
  data: BarMiniDatum[];
  color?: string;
  valueFormat?: BarMiniValueFormat;
}) {
  return (
    <ResponsiveContainer width="100%" height={64}>
      <BarChart data={data} margin={{ top: 4, right: 0, bottom: 0, left: 0 }}>
        <XAxis dataKey="label" hide />
        <Tooltip
          cursor={{ fill: "rgba(255,255,255,0.06)" }}
          contentStyle={{
            background: "#111111",
            border: "1px solid rgba(255,255,255,0.14)",
            borderRadius: 8,
            fontSize: 12,
          }}
          labelStyle={{ color: "#f5f5f0" }}
          formatter={(value) => {
            const numeric = typeof value === "number" ? value : Number(Array.isArray(value) ? value[0] : value);
            return [formatValue(numeric, valueFormat), ""];
          }}
        />
        <Bar dataKey="value" fill={color} radius={[4, 4, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  );
}
