"use client";

import { useState } from "react";
import {
  DEFAULT_PERFORMANCE_PERIOD,
  PERFORMANCE_PERIOD_LABEL,
  PERFORMANCE_PERIODS,
  type PerformancePeriod,
} from "@/lib/dashboard/periods";
import type { Section } from "@/lib/dashboard/section";
import type {
  BookingMixEntry,
  ByPeriod,
  DestinationRanking,
  ModerationStats,
} from "@/lib/dashboard/types";
import { BookingMixCard } from "./BookingMixCard";
import { DestinationRankingCard } from "./DestinationRankingCard";
import { ModerationCard } from "./ModerationCard";
import { SegmentToggle } from "./primitives/SegmentToggle";

/**
 * Month / Quarter / Year toggle for the three Performance Overview cards. The
 * server sends all three windows up front, so switching is instant and needs
 * no round trip. Quarter (90 days) is the default — the window Top
 * Destinations has always used.
 */
export function PerformanceOverview({
  destinations,
  bookingMix,
  moderation,
}: {
  destinations: Section<ByPeriod<DestinationRanking>>;
  bookingMix: Section<ByPeriod<BookingMixEntry[]>>;
  moderation: Section<ByPeriod<ModerationStats>>;
}) {
  const [period, setPeriod] = useState<PerformancePeriod>(DEFAULT_PERFORMANCE_PERIOD);

  return (
    <section aria-labelledby="performance-overview-heading" className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2
          id="performance-overview-heading"
          className="text-sm font-semibold tracking-wide text-white/90 uppercase"
        >
          Performance Overview
        </h2>
        <SegmentToggle
          label="Performance period"
          options={PERFORMANCE_PERIODS.map((value) => ({ value, label: PERFORMANCE_PERIOD_LABEL[value] }))}
          value={period}
          onChange={(value) => setPeriod(value as PerformancePeriod)}
        />
      </div>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <DestinationRankingCard section={destinations} period={period} index={10} />
        <BookingMixCard section={bookingMix} period={period} index={11} />
        <ModerationCard section={moderation} period={period} index={12} />
      </div>
    </section>
  );
}
