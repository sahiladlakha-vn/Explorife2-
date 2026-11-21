import { describe, expect, it, vi, beforeEach } from "vitest";

// `cacheLife()` throws unless it's called inside a real Next.js Cache
// Components render (see node_modules/next/dist/server/use-cache/cache-life.js)
// — mocked here the same way lib/auth/guards.test.ts mocks next/navigation's
// redirect(), so these functions are testable as plain async functions.
vi.mock("next/cache", () => ({
  cacheLife: vi.fn(),
}));

vi.mock("@/lib/db", () => ({
  prisma: {
    profile: {
      count: vi.fn(),
    },
    trip: {
      findMany: vi.fn(),
      findFirst: vi.fn(),
    },
    tripBooking: {
      aggregate: vi.fn(),
      groupBy: vi.fn(),
      findMany: vi.fn(),
    },
    curatedCollection: {
      findMany: vi.fn(),
    },
    $queryRaw: vi.fn(),
  },
}));

import { prisma } from "@/lib/db";
import {
  getTotalUsers,
  getTripsInProgress,
  getUpcomingBookingCoverage,
  getModerationStats,
  getBookingValueSummary,
  getBookingVelocity,
  getBookingFunnel,
  getUpcomingWeek,
  getRecentBookings,
  getBookingMixByPeriod,
  getModerationByPeriod,
  getDestinationRankingByPeriod,
} from "./admin-dashboard";

beforeEach(() => {
  vi.resetAllMocks();
});

/** The values a tagged-template `$queryRaw` call interpolated (index 0 of `calls[n]` is the SQL strings). */
function boundValues(callIndex: number): unknown[] {
  return vi.mocked(prisma.$queryRaw).mock.calls[callIndex]!.slice(1);
}

describe("getTotalUsers", () => {
  it("returns the profile count", async () => {
    vi.mocked(prisma.profile.count).mockResolvedValue(42);
    await expect(getTotalUsers()).resolves.toBe(42);
  });
});

describe("getTripsInProgress", () => {
  it("computes the active and completed percentages", async () => {
    vi.mocked(prisma.$queryRaw).mockResolvedValue([
      { activeCount: 3, completedCount: 6, totalCount: 12 },
    ]);
    await expect(getTripsInProgress()).resolves.toEqual({
      activeCount: 3,
      completedCount: 6,
      totalCount: 12,
      percentage: 25,
      completedPercentage: 50,
    });
  });

  it("returns 0% rather than dividing by zero when there are no trips", async () => {
    vi.mocked(prisma.$queryRaw).mockResolvedValue([
      { activeCount: 0, completedCount: 0, totalCount: 0 },
    ]);
    await expect(getTripsInProgress()).resolves.toEqual({
      activeCount: 0,
      completedCount: 0,
      totalCount: 0,
      percentage: 0,
      completedPercentage: 0,
    });
  });
});

describe("getUpcomingBookingCoverage", () => {
  it("computes the coverage percentage", async () => {
    vi.mocked(prisma.$queryRaw).mockResolvedValue([{ upcomingCount: 8, withBookingCount: 6 }]);
    await expect(getUpcomingBookingCoverage()).resolves.toEqual({
      upcomingCount: 8,
      withBookingCount: 6,
      percentage: 75,
    });
  });

  it("returns 0% rather than dividing by zero when there are no upcoming trips", async () => {
    vi.mocked(prisma.$queryRaw).mockResolvedValue([{ upcomingCount: 0, withBookingCount: 0 }]);
    await expect(getUpcomingBookingCoverage()).resolves.toEqual({
      upcomingCount: 0,
      withBookingCount: 0,
      percentage: 0,
    });
  });
});

describe("getModerationStats", () => {
  it("computes percentage and converts avg turnaround seconds to hours", async () => {
    vi.mocked(prisma.$queryRaw).mockResolvedValue([
      { totalListings: 20, verifiedCount: 15, pendingCount: 5, avgTurnaroundSeconds: 7200 },
    ]);
    await expect(getModerationStats()).resolves.toEqual({
      totalListings: 20,
      verifiedCount: 15,
      pendingCount: 5,
      percentage: 75,
      avgTurnaroundHours: 2,
    });
  });

  it("keeps avgTurnaroundHours null when nothing has been verified yet", async () => {
    vi.mocked(prisma.$queryRaw).mockResolvedValue([
      { totalListings: 5, verifiedCount: 0, pendingCount: 5, avgTurnaroundSeconds: null },
    ]);
    await expect(getModerationStats()).resolves.toEqual({
      totalListings: 5,
      verifiedCount: 0,
      pendingCount: 5,
      percentage: 0,
      avgTurnaroundHours: null,
    });
  });
});

describe("getBookingValueSummary", () => {
  /** 14 zero-filled Vietnam days, 2026-11-08 .. 2026-11-21: 10 tr a day, then 15 tr a day. */
  const fourteenDays = Array.from({ length: 14 }, (_, i) => ({
    day: `2026-11-${String(8 + i).padStart(2, "0")}`,
    count: i % 2,
    amountVnd: i < 7 ? 10_000_000 : 15_000_000,
  }));

  function mockAggregate(sum: bigint | null, count: number) {
    vi.mocked(prisma.tripBooking.aggregate).mockResolvedValue({
      _sum: { amountVnd: sum },
      _count: count,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only _sum/_count are read
    } as any);
  }

  it("combines the lifetime paid aggregate with the series and the week-over-week change", async () => {
    mockAggregate(BigInt(1_200_000_000), 42);
    vi.mocked(prisma.$queryRaw).mockResolvedValue(fourteenDays);

    await expect(getBookingValueSummary()).resolves.toEqual({
      paidVnd: 1_200_000_000,
      paidCount: 42,
      daily: fourteenDays,
      last7Vnd: 105_000_000,
      prev7Vnd: 70_000_000,
      changePercent: 50,
    });
    expect(prisma.tripBooking.aggregate).toHaveBeenCalledWith({
      where: { status: "paid" },
      _sum: { amountVnd: true },
      _count: true,
    });
  });

  it("reports a decrease as a negative percentage", async () => {
    mockAggregate(BigInt(1), 1);
    vi.mocked(prisma.$queryRaw).mockResolvedValue(
      fourteenDays.map((d, i) => ({ ...d, amountVnd: i < 7 ? 20_000_000 : 10_000_000 })),
    );
    const summary = await getBookingValueSummary();
    expect(summary.changePercent).toBe(-50);
  });

  it("has no percentage change when the previous week had nothing paid (no baseline)", async () => {
    mockAggregate(BigInt(5_000_000), 1);
    vi.mocked(prisma.$queryRaw).mockResolvedValue(
      fourteenDays.map((d, i) => ({ ...d, amountVnd: i === 13 ? 5_000_000 : 0 })),
    );
    await expect(getBookingValueSummary()).resolves.toMatchObject({
      last7Vnd: 5_000_000,
      prev7Vnd: 0,
      changePercent: null,
    });
  });

  it("defaults everything to 0 when there are no paid bookings at all", async () => {
    mockAggregate(null, 0);
    vi.mocked(prisma.$queryRaw).mockResolvedValue([]);

    await expect(getBookingValueSummary()).resolves.toEqual({
      paidVnd: 0,
      paidCount: 0,
      daily: [],
      last7Vnd: 0,
      prev7Vnd: 0,
      changePercent: null,
    });
  });
});

describe("getBookingVelocity", () => {
  it("returns the per-day counts and their total", async () => {
    const daily = [
      { day: "2026-11-20", count: 3 },
      { day: "2026-11-21", count: 4 },
    ];
    vi.mocked(prisma.$queryRaw).mockResolvedValue(daily);
    await expect(getBookingVelocity()).resolves.toEqual({ daily, total: 7 });
  });

  it("returns a zero total for an empty series", async () => {
    vi.mocked(prisma.$queryRaw).mockResolvedValue([]);
    await expect(getBookingVelocity()).resolves.toEqual({ daily: [], total: 0 });
  });
});

describe("getBookingFunnel", () => {
  it("builds cumulative stages from per-status counts", async () => {
    vi.mocked(prisma.tripBooking.groupBy).mockResolvedValue([
      { status: "to_book", _count: 10 },
      { status: "booked", _count: 7 },
      { status: "paid", _count: 4 },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- groupBy row shape depends on the `by`/`_count` args
    ] as any);

    await expect(getBookingFunnel()).resolves.toEqual({
      toBook: 21,
      booked: 11,
      paid: 4,
    });
  });

  it("treats a missing status as 0 rather than throwing", async () => {
    vi.mocked(prisma.tripBooking.groupBy).mockResolvedValue([
      { status: "to_book", _count: 5 },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- groupBy row shape depends on the `by`/`_count` args
    ] as any);

    await expect(getBookingFunnel()).resolves.toEqual({
      toBook: 5,
      booked: 0,
      paid: 0,
    });
  });
});

describe("getUpcomingWeek", () => {
  const SELECT = { id: true, name: true, location: true, startDate: true, endDate: true };

  const sapa = {
    id: "trip-1",
    name: "Sapa Trekking",
    location: "Sapa",
    startDate: new Date("2026-11-18T00:00:00.000Z"),
    endDate: new Date("2026-11-23T00:00:00.000Z"),
  };
  const phuQuoc = {
    id: "trip-2",
    name: "Phu Quoc Getaway",
    location: "Phu Quoc",
    startDate: new Date("2026-11-30T00:00:00.000Z"),
    endDate: new Date("2026-12-06T00:00:00.000Z"),
  };

  beforeEach(() => {
    vi.mocked(prisma.$queryRaw).mockResolvedValue([{ weekStart: "2026-11-16", today: "2026-11-19" }]);
  });

  it("returns the Vietnam week, the trips overlapping it, and the next trip after it as plain days", async () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only the selected fields are read
    vi.mocked(prisma.trip.findMany).mockResolvedValue([sapa] as any);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only the selected fields are read
    vi.mocked(prisma.trip.findFirst).mockResolvedValue(phuQuoc as any);

    await expect(getUpcomingWeek()).resolves.toEqual({
      weekStart: "2026-11-16",
      today: "2026-11-19",
      trips: [
        { id: "trip-1", name: "Sapa Trekking", location: "Sapa", startDate: "2026-11-18", endDate: "2026-11-23" },
      ],
      nextTrip: {
        id: "trip-2",
        name: "Phu Quoc Getaway",
        location: "Phu Quoc",
        startDate: "2026-11-30",
        endDate: "2026-12-06",
      },
    });
  });

  it("queries trips overlapping Monday..Sunday and the first trip starting after Sunday", async () => {
    vi.mocked(prisma.trip.findMany).mockResolvedValue([]);
    vi.mocked(prisma.trip.findFirst).mockResolvedValue(null);

    await getUpcomingWeek();

    expect(prisma.trip.findMany).toHaveBeenCalledWith({
      where: {
        startDate: { lte: new Date("2026-11-22T00:00:00.000Z") },
        endDate: { gte: new Date("2026-11-16T00:00:00.000Z") },
      },
      orderBy: [{ startDate: "asc" }, { endDate: "asc" }],
      take: 12,
      select: SELECT,
    });
    expect(prisma.trip.findFirst).toHaveBeenCalledWith({
      where: { startDate: { gt: new Date("2026-11-22T00:00:00.000Z") } },
      orderBy: { startDate: "asc" },
      select: SELECT,
    });
  });

  it("returns no trips and a null next trip on an empty calendar", async () => {
    vi.mocked(prisma.trip.findMany).mockResolvedValue([]);
    vi.mocked(prisma.trip.findFirst).mockResolvedValue(null);

    await expect(getUpcomingWeek()).resolves.toEqual({
      weekStart: "2026-11-16",
      today: "2026-11-19",
      trips: [],
      nextTrip: null,
    });
  });
});

describe("getRecentBookings", () => {
  it("includes only trip name, type, amount, status, and date — never user contact info", async () => {
    vi.mocked(prisma.tripBooking.findMany).mockResolvedValue([
      {
        id: "booking-1",
        bookingType: "flight",
        amountVnd: BigInt(2_500_000),
        status: "paid",
        createdAt: new Date("2026-11-01T08:00:00.000Z"),
        trip: { name: "Da Nang Beach Week" },
      },
      {
        id: "booking-2",
        bookingType: "stay",
        amountVnd: null,
        status: "to_book",
        createdAt: new Date("2026-11-02T08:00:00.000Z"),
        trip: { name: "Hanoi Weekend" },
      },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only the selected fields are read
    ] as any);

    await expect(getRecentBookings()).resolves.toEqual([
      {
        id: "booking-1",
        tripName: "Da Nang Beach Week",
        bookingType: "flight",
        amountVnd: 2_500_000,
        status: "paid",
        createdAt: "2026-11-01T08:00:00.000Z",
      },
      {
        id: "booking-2",
        tripName: "Hanoi Weekend",
        bookingType: "stay",
        amountVnd: null,
        status: "to_book",
        createdAt: "2026-11-02T08:00:00.000Z",
      },
    ]);
    expect(prisma.tripBooking.findMany).toHaveBeenCalledWith({
      orderBy: { createdAt: "desc" },
      take: 8,
      select: {
        id: true,
        bookingType: true,
        amountVnd: true,
        status: true,
        createdAt: true,
        trip: { select: { name: true } },
      },
    });
  });
});

describe("getBookingMixByPeriod", () => {
  it("runs one query per window (30 / 90 / 365 days) and zero-fills the known booking types", async () => {
    vi.mocked(prisma.$queryRaw)
      .mockResolvedValueOnce([{ bookingType: "flight", count: 3, amountVnd: 300 }])
      .mockResolvedValueOnce([
        { bookingType: "stay", count: 2, amountVnd: 200 },
        { bookingType: "visa", count: 1, amountVnd: 10 },
      ])
      .mockResolvedValueOnce([]);

    const mix = await getBookingMixByPeriod();

    expect([boundValues(0), boundValues(1), boundValues(2)]).toEqual([[30], [90], [365]]);
    expect(mix.month).toEqual([
      { bookingType: "flight", count: 3, amountVnd: 300 },
      { bookingType: "stay", count: 0, amountVnd: 0 },
      { bookingType: "activity", count: 0, amountVnd: 0 },
      { bookingType: "transport", count: 0, amountVnd: 0 },
    ]);
    expect(mix.quarter.map((m) => m.bookingType)).toEqual([
      "flight",
      "stay",
      "activity",
      "transport",
      "visa",
    ]);
    expect(mix.quarter[1]).toEqual({ bookingType: "stay", count: 2, amountVnd: 200 });
    expect(mix.year.every((m) => m.count === 0 && m.amountVnd === 0)).toBe(true);
  });
});

describe("getModerationByPeriod", () => {
  it("computes stats per window, binding the same day count to both listing tables", async () => {
    vi.mocked(prisma.$queryRaw)
      .mockResolvedValueOnce([{ totalListings: 10, verifiedCount: 5, pendingCount: 5, avgTurnaroundSeconds: 3600 }])
      .mockResolvedValueOnce([{ totalListings: 0, verifiedCount: 0, pendingCount: 0, avgTurnaroundSeconds: null }])
      .mockResolvedValueOnce([{ totalListings: 4, verifiedCount: 3, pendingCount: 1, avgTurnaroundSeconds: 14_400 }]);

    const result = await getModerationByPeriod();

    expect([boundValues(0), boundValues(1), boundValues(2)]).toEqual([
      [30, 30],
      [90, 90],
      [365, 365],
    ]);
    expect(result.month).toEqual({
      totalListings: 10,
      verifiedCount: 5,
      pendingCount: 5,
      percentage: 50,
      avgTurnaroundHours: 1,
    });
    expect(result.quarter).toEqual({
      totalListings: 0,
      verifiedCount: 0,
      pendingCount: 0,
      percentage: 0,
      avgTurnaroundHours: null,
    });
    expect(result.year.percentage).toBe(75);
    expect(result.year.avgTurnaroundHours).toBe(4);
  });
});

describe("getDestinationRankingByPeriod", () => {
  /** `$queryRaw` is called once per window in month, quarter, year order. */
  function mockUsage(month: unknown[], quarter: unknown[], year: unknown[]) {
    vi.mocked(prisma.$queryRaw)
      .mockResolvedValueOnce(month)
      .mockResolvedValueOnce(quarter)
      .mockResolvedValueOnce(year);
  }

  function mockCollections(rows: { title: string; scopeValue: string }[]) {
    vi.mocked(prisma.curatedCollection.findMany).mockResolvedValue(
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `title` / `scopeValue` are selected
      rows as any,
    );
  }

  it("queries each window (30 / 90 / 365 days) and loads the collections once", async () => {
    mockUsage([{ location: "Sapa", tripCount: 1 }], [], []);
    mockCollections([]);

    await getDestinationRankingByPeriod();

    expect([boundValues(0), boundValues(1), boundValues(2)]).toEqual([[30], [90], [365]]);
    expect(prisma.curatedCollection.findMany).toHaveBeenCalledTimes(1);
    expect(prisma.curatedCollection.findMany).toHaveBeenCalledWith({
      where: { isDestination: true },
      orderBy: { sortOrder: "asc" },
      select: { title: true, scopeValue: true },
    });
  });

  it("computes the featured flag via normalizeDestination, matching across diacritics and aliases", async () => {
    const rows = [
      { location: "Da Nang", tripCount: 12 },
      { location: "Ho Chi Minh City", tripCount: 8 },
      { location: "Sapa", tripCount: 5 },
    ];
    mockUsage(rows, rows, rows);
    mockCollections([
      { title: "Da Nang", scopeValue: "Đà Nẵng" },
      { title: "Saigon", scopeValue: "Saigon" },
    ]);

    const result = await getDestinationRankingByPeriod();

    expect(result.quarter).toEqual({
      mode: "usage",
      items: [
        { location: "Da Nang", tripCount: 12, featured: true },
        { location: "Ho Chi Minh City", tripCount: 8, featured: true },
        { location: "Sapa", tripCount: 5, featured: false },
      ],
    });
  });

  it("merges destinations sharing a normalized key, summing counts and labeling with the most common original spelling", async () => {
    const rows = [
      { location: "Ho Chi Minh City", tripCount: 7 },
      { location: "Saigon", tripCount: 5 },
      { location: "HCMC", tripCount: 2 },
      { location: "Sapa", tripCount: 4 },
    ];
    mockUsage(rows, rows, rows);
    mockCollections([]);

    const result = await getDestinationRankingByPeriod();

    expect(result.year).toEqual({
      mode: "usage",
      items: [
        { location: "Ho Chi Minh City", tripCount: 14, featured: false },
        { location: "Sapa", tripCount: 4, featured: false },
      ],
    });
  });

  describe("real-world location strings (geocoder output mixed with typed text)", () => {
    it("merges a geocoder string with the typed spellings of the same place and shows the place name", async () => {
      // The shapes found in the production trips table.
      const rows = [
        { location: "Hội An, An Giang, Vietnam", tripCount: 3 },
        { location: "Da Nang, Vietnam", tripCount: 2 },
        { location: "da nang", tripCount: 1 },
        { location: "Da nang", tripCount: 1 },
        { location: "hoi an", tripCount: 1 },
        { location: "Hamburg, Germany", tripCount: 1 },
      ];
      mockUsage(rows, rows, rows);
      mockCollections([]);

      const result = await getDestinationRankingByPeriod();

      expect(result.year).toEqual({
        mode: "usage",
        items: [
          { location: "Da Nang", tripCount: 4, featured: false },
          { location: "Hội An", tripCount: 4, featured: false },
          { location: "Hamburg, Germany", tripCount: 1, featured: false },
        ],
      });
    });

    it('does not fold a "Saigon" in another country into Ho Chi Minh City', async () => {
      const rows = [
        { location: "Ho Chi Minh City, Vietnam", tripCount: 2 },
        { location: "Saigon", tripCount: 1 },
        {
          location: "Saigon, 78132, Pontianak Timur, Pontianak, West Kalimantan, Indonesia",
          tripCount: 1,
        },
      ];
      mockUsage(rows, rows, rows);
      mockCollections([{ title: "Explore Ho Chi Minh City", scopeValue: "Ho Chi Minh City" }]);

      const result = await getDestinationRankingByPeriod();

      expect(result.quarter).toEqual({
        mode: "usage",
        items: [
          { location: "Ho Chi Minh City", tripCount: 3, featured: true },
          { location: "Saigon, Indonesia", tripCount: 1, featured: false },
        ],
      });
    });

    it("gives the Featured badge to geocoder strings and accented spellings of a featured destination", async () => {
      const rows = [
        { location: "Ho Chi Minh City, Vietnam", tripCount: 2 },
        { location: "Hà Nội, Việt Nam", tripCount: 1 },
        { location: "Da Nang, Vietnam", tripCount: 1 },
      ];
      mockUsage(rows, rows, rows);
      mockCollections([
        { title: "Explore Hanoi", scopeValue: "Hanoi" },
        { title: "Explore Ho Chi Minh City", scopeValue: "Ho Chi Minh City" },
      ]);

      const result = await getDestinationRankingByPeriod();

      expect(result.year).toEqual({
        mode: "usage",
        items: [
          { location: "Ho Chi Minh City", tripCount: 2, featured: true },
          { location: "Da Nang", tripCount: 1, featured: false },
          { location: "Hà Nội", tripCount: 1, featured: true },
        ],
      });
    });

    it("picks the same label and order whatever order the database returns the rows in", async () => {
      const rows = [
        { location: "da nang", tripCount: 1 },
        { location: "Da nang", tripCount: 1 },
        { location: "Da Nang", tripCount: 1 },
        { location: "Hamburg, Germany", tripCount: 1 },
        { location: "Hamburg, Hamburg, Germany", tripCount: 1 },
      ];
      const orderings = [rows, [...rows].reverse(), [rows[2]!, rows[4]!, rows[0]!, rows[3]!, rows[1]!]];

      const results = [];
      for (const ordering of orderings) {
        mockUsage(ordering, ordering, ordering);
        mockCollections([]);
        results.push((await getDestinationRankingByPeriod()).year);
      }

      for (const result of results) {
        expect(result).toEqual({
          mode: "usage",
          items: [
            // A three-way tie on one vote each: the capitalised spelling wins, "Da Nang" before "Da nang".
            { location: "Da Nang", tripCount: 3, featured: false },
            { location: "Hamburg, Germany", tripCount: 2, featured: false },
          ],
        });
      }
    });
  });

  it("caps each ranking at 6 entries", async () => {
    const rows = Array.from({ length: 8 }, (_, i) => ({ location: `Place ${i}`, tripCount: 8 - i }));
    mockUsage(rows, rows, rows);
    mockCollections([]);

    const result = await getDestinationRankingByPeriod();
    for (const period of ["month", "quarter", "year"] as const) {
      expect(result[period].mode).toBe("usage");
      expect(result[period].items).toHaveLength(6);
    }
  });

  it("gives a quiet window an honest empty list while other windows still rank", async () => {
    mockUsage([], [{ location: "Sapa", tripCount: 3 }], [{ location: "Sapa", tripCount: 9 }]);
    mockCollections([{ title: "Sapa", scopeValue: "Sapa" }]);

    const result = await getDestinationRankingByPeriod();

    expect(result.month).toEqual({ mode: "usage", items: [] });
    expect(result.quarter).toEqual({
      mode: "usage",
      items: [{ location: "Sapa", tripCount: 3, featured: true }],
    });
  });

  it("falls back to the editorial CuratedCollection ranking for every window when there are no trips at all", async () => {
    mockUsage([], [], []);
    mockCollections([
      { title: "Sapa", scopeValue: "Sapa" },
      { title: "Ha Long Bay", scopeValue: "Ha Long Bay" },
    ]);

    const result = await getDestinationRankingByPeriod();
    const editorial = { mode: "editorial", items: [{ title: "Sapa" }, { title: "Ha Long Bay" }] };

    expect(result).toEqual({ month: editorial, quarter: editorial, year: editorial });
  });
});
