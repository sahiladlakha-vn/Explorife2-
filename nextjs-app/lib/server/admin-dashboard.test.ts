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
  getBookingFunnel,
  getUpcomingTrips,
  getRecentBookings,
  getBookingMix,
  getDestinationRanking,
} from "./admin-dashboard";

beforeEach(() => {
  vi.clearAllMocks();
});

describe("getTotalUsers", () => {
  it("returns the profile count", async () => {
    vi.mocked(prisma.profile.count).mockResolvedValue(42);
    await expect(getTotalUsers()).resolves.toBe(42);
  });
});

describe("getTripsInProgress", () => {
  it("computes the active percentage", async () => {
    vi.mocked(prisma.$queryRaw).mockResolvedValue([{ activeCount: 3, totalCount: 12 }]);
    await expect(getTripsInProgress()).resolves.toEqual({
      activeCount: 3,
      totalCount: 12,
      percentage: 25,
    });
  });

  it("returns 0% rather than dividing by zero when there are no trips", async () => {
    vi.mocked(prisma.$queryRaw).mockResolvedValue([{ activeCount: 0, totalCount: 0 }]);
    await expect(getTripsInProgress()).resolves.toEqual({
      activeCount: 0,
      totalCount: 0,
      percentage: 0,
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
  it("combines the paid aggregate with the daily series", async () => {
    vi.mocked(prisma.tripBooking.aggregate).mockResolvedValue({
      _sum: { amountVnd: BigInt(1_200_000_000) },
      _count: 42,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only _sum/_count are read
    } as any);
    vi.mocked(prisma.$queryRaw).mockResolvedValue([
      { day: "2026-11-08", count: 2, amountVnd: 50_000_000 },
      { day: "2026-11-09", count: 1, amountVnd: 25_000_000 },
    ]);

    await expect(getBookingValueSummary()).resolves.toEqual({
      paidVnd: 1_200_000_000,
      paidCount: 42,
      daily: [
        { day: "2026-11-08", count: 2, amountVnd: 50_000_000 },
        { day: "2026-11-09", count: 1, amountVnd: 25_000_000 },
      ],
    });
    expect(prisma.tripBooking.aggregate).toHaveBeenCalledWith({
      where: { status: "paid" },
      _sum: { amountVnd: true },
      _count: true,
    });
  });

  it("defaults paidVnd to 0 when there are no paid bookings at all", async () => {
    vi.mocked(prisma.tripBooking.aggregate).mockResolvedValue({
      _sum: { amountVnd: null },
      _count: 0,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only _sum/_count are read
    } as any);
    vi.mocked(prisma.$queryRaw).mockResolvedValue([]);

    await expect(getBookingValueSummary()).resolves.toEqual({
      paidVnd: 0,
      paidCount: 0,
      daily: [],
    });
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

describe("getUpcomingTrips", () => {
  it("maps trips to ISO date strings, querying only startDate > today", async () => {
    vi.mocked(prisma.trip.findMany).mockResolvedValue([
      {
        id: "trip-1",
        name: "Sapa Trekking",
        location: "Sapa",
        startDate: new Date("2026-12-01T00:00:00.000Z"),
        endDate: new Date("2026-12-05T00:00:00.000Z"),
      },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only the selected fields are read
    ] as any);

    await expect(getUpcomingTrips()).resolves.toEqual([
      {
        id: "trip-1",
        name: "Sapa Trekking",
        location: "Sapa",
        startDate: "2026-12-01T00:00:00.000Z",
        endDate: "2026-12-05T00:00:00.000Z",
      },
    ]);
    expect(prisma.trip.findMany).toHaveBeenCalledWith({
      where: { startDate: { gt: expect.any(Date) } },
      orderBy: { startDate: "asc" },
      take: 6,
      select: { id: true, name: true, location: true, startDate: true, endDate: true },
    });
  });

  it("returns an empty list when there are no upcoming trips", async () => {
    vi.mocked(prisma.trip.findMany).mockResolvedValue([]);
    await expect(getUpcomingTrips()).resolves.toEqual([]);
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

describe("getBookingMix", () => {
  it("maps grouped rows, converting the summed BigInt to a number", async () => {
    vi.mocked(prisma.tripBooking.groupBy).mockResolvedValue([
      { bookingType: "flight", _count: 10, _sum: { amountVnd: BigInt(300_000_000) } },
      { bookingType: "stay", _count: 6, _sum: { amountVnd: null } },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- groupBy row shape depends on the `by`/`_count`/`_sum` args
    ] as any);

    await expect(getBookingMix()).resolves.toEqual([
      { bookingType: "flight", count: 10, amountVnd: 300_000_000 },
      { bookingType: "stay", count: 6, amountVnd: 0 },
    ]);
  });
});

describe("getDestinationRanking", () => {
  it("computes the featured flag via normalizeDestination, matching across diacritics and aliases", async () => {
    vi.mocked(prisma.$queryRaw).mockResolvedValue([
      { location: "Da Nang", tripCount: 12 },
      { location: "Ho Chi Minh City", tripCount: 8 },
      { location: "Sapa", tripCount: 5 },
    ]);
    vi.mocked(prisma.curatedCollection.findMany).mockResolvedValue([
      { scopeValue: "Đà Nẵng" },
      { scopeValue: "Saigon" },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `scopeValue` is selected
    ] as any);

    await expect(getDestinationRanking()).resolves.toEqual({
      mode: "usage",
      items: [
        { location: "Da Nang", tripCount: 12, featured: true },
        { location: "Ho Chi Minh City", tripCount: 8, featured: true },
        { location: "Sapa", tripCount: 5, featured: false },
      ],
    });
    expect(prisma.curatedCollection.findMany).toHaveBeenCalledWith({
      where: { isDestination: true },
      select: { scopeValue: true },
    });
  });

  it("merges destinations sharing a normalized key, summing counts and labeling with the most common original spelling", async () => {
    vi.mocked(prisma.$queryRaw).mockResolvedValue([
      { location: "Ho Chi Minh City", tripCount: 7 },
      { location: "Saigon", tripCount: 5 },
      { location: "HCMC", tripCount: 2 },
      { location: "Sapa", tripCount: 4 },
    ]);
    vi.mocked(prisma.curatedCollection.findMany).mockResolvedValue([]);

    await expect(getDestinationRanking()).resolves.toEqual({
      mode: "usage",
      items: [
        { location: "Ho Chi Minh City", tripCount: 14, featured: false },
        { location: "Sapa", tripCount: 4, featured: false },
      ],
    });
  });

  it("caps the merged ranking at 6 entries", async () => {
    vi.mocked(prisma.$queryRaw).mockResolvedValue(
      Array.from({ length: 8 }, (_, i) => ({ location: `Place ${i}`, tripCount: 8 - i })),
    );
    vi.mocked(prisma.curatedCollection.findMany).mockResolvedValue([]);

    const result = await getDestinationRanking();
    expect(result.mode).toBe("usage");
    expect(result.items).toHaveLength(6);
  });

  it("falls back to the editorial CuratedCollection ranking when there's no usage data", async () => {
    vi.mocked(prisma.$queryRaw).mockResolvedValue([]);
    vi.mocked(prisma.curatedCollection.findMany).mockResolvedValue([
      { title: "Sapa" },
      { title: "Ha Long Bay" },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `title` is selected
    ] as any);

    await expect(getDestinationRanking()).resolves.toEqual({
      mode: "editorial",
      items: [{ title: "Sapa" }, { title: "Ha Long Bay" }],
    });
    expect(prisma.curatedCollection.findMany).toHaveBeenCalledTimes(1);
    expect(prisma.curatedCollection.findMany).toHaveBeenCalledWith({
      where: { isDestination: true },
      orderBy: { sortOrder: "asc" },
      take: 6,
      select: { title: true },
    });
  });
});
