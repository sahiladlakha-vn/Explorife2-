import { describe, it, expect, vi, beforeEach } from "vitest";
import type { User } from "@supabase/supabase-js";

// Same mocking approach as lib/server/profiles.test.ts: `createClient()` and
// `prisma` are mocked rather than hit for real. `requireUser()` itself is
// NOT mocked — it's exercised for real against the mocked Supabase client,
// same as every other lib/server/*.test.ts file, so these tests also pin
// down "no session -> AuthError" without needing their own copy of that
// logic.
vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(),
}));
vi.mock("@/lib/db", () => ({
  prisma: {
    trip: {
      findUnique: vi.fn(),
      findMany: vi.fn(),
    },
    tripCollaborator: {
      findUnique: vi.fn(),
    },
  },
}));

import { createClient } from "@/lib/supabase/server";
import { prisma } from "@/lib/db";
import { AuthError } from "@/lib/auth/permissions";
import {
  requireTripAccess,
  getTripForUser,
  listTripsForUser,
  getActiveTripId,
} from "./trips";

function mockSessionUser(user: Pick<User, "id"> | null) {
  vi.mocked(createClient).mockResolvedValue({
    auth: {
      getUser: vi.fn().mockResolvedValue({ data: { user } }),
    },
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- partial Supabase client stub, only `auth.getUser()` is exercised
  } as any);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any -- test double, only the fields requireTripAccess/listTripsForUser read
function trip(overrides: Partial<any> = {}): any {
  return {
    id: "trip-1",
    ownerId: "owner-1",
    name: "Sapa trek",
    startDate: new Date("2026-01-01T00:00:00.000Z"),
    endDate: new Date("2026-01-05T00:00:00.000Z"),
    ...overrides,
  };
}

/** `notFound()` throws a plain Error with a `NEXT_HTTP_ERROR_FALLBACK;404` digest — assert on that rather than a specific Error subclass, since `notFound()` isn't one. */
async function expectNotFound(promise: Promise<unknown>) {
  let thrown: unknown;
  try {
    await promise;
  } catch (err) {
    thrown = err;
  }
  expect(thrown).toBeDefined();
  expect((thrown as { digest?: string })?.digest).toMatch(/^NEXT_HTTP_ERROR_FALLBACK;404/);
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("requireTripAccess", () => {
  it("throws AuthError when there's no session", async () => {
    mockSessionUser(null);
    await expect(requireTripAccess("trip-1")).rejects.toBeInstanceOf(AuthError);
    expect(prisma.trip.findUnique).not.toHaveBeenCalled();
  });

  it("calls notFound() when the trip doesn't exist", async () => {
    mockSessionUser({ id: "owner-1" });
    vi.mocked(prisma.trip.findUnique).mockResolvedValue(null);
    await expectNotFound(requireTripAccess("missing-trip"));
    expect(prisma.tripCollaborator.findUnique).not.toHaveBeenCalled();
  });

  it("lets the owner through without a collaborator lookup", async () => {
    mockSessionUser({ id: "owner-1" });
    const t = trip();
    vi.mocked(prisma.trip.findUnique).mockResolvedValue(t);
    const result = await requireTripAccess("trip-1");
    expect(result).toEqual({ user: { id: "owner-1" }, trip: t });
    expect(prisma.tripCollaborator.findUnique).not.toHaveBeenCalled();
  });

  it("lets a confirmed collaborator through", async () => {
    mockSessionUser({ id: "collab-1" });
    vi.mocked(prisma.trip.findUnique).mockResolvedValue(trip());
    vi.mocked(prisma.tripCollaborator.findUnique).mockResolvedValue(
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `status` is selected
      { status: "confirmed" } as any,
    );
    const result = await requireTripAccess("trip-1");
    expect(result.user).toEqual({ id: "collab-1" });
    expect(prisma.tripCollaborator.findUnique).toHaveBeenCalledWith({
      where: { tripId_userId: { tripId: "trip-1", userId: "collab-1" } },
      select: { status: true },
    });
  });

  // Explicitly requested case: a trip that exists, where the caller is
  // neither the owner nor any kind of collaborator at all, must 404 — not
  // leak whether the trip exists via a 403.
  it("calls notFound() when the trip exists but the user is neither owner nor collaborator", async () => {
    mockSessionUser({ id: "stranger-1" });
    vi.mocked(prisma.trip.findUnique).mockResolvedValue(trip());
    vi.mocked(prisma.tripCollaborator.findUnique).mockResolvedValue(null);
    await expectNotFound(requireTripAccess("trip-1"));
  });

  // Explicitly requested case: an invited-but-not-yet-accepted collaborator
  // must NOT get access — "pending" is not "confirmed".
  it("calls notFound() when the collaborator invite is still pending", async () => {
    mockSessionUser({ id: "pending-collab-1" });
    vi.mocked(prisma.trip.findUnique).mockResolvedValue(trip());
    vi.mocked(prisma.tripCollaborator.findUnique).mockResolvedValue(
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only `status` is selected
      { status: "pending" } as any,
    );
    await expectNotFound(requireTripAccess("trip-1"));
  });
});

describe("getTripForUser", () => {
  it("returns just the trip when access is granted", async () => {
    mockSessionUser({ id: "owner-1" });
    const t = trip();
    vi.mocked(prisma.trip.findUnique).mockResolvedValue(t);
    await expect(getTripForUser("trip-1")).resolves.toEqual(t);
  });

  it("calls notFound() when access is denied, same as requireTripAccess", async () => {
    mockSessionUser({ id: "stranger-1" });
    vi.mocked(prisma.trip.findUnique).mockResolvedValue(trip());
    vi.mocked(prisma.tripCollaborator.findUnique).mockResolvedValue(null);
    await expectNotFound(getTripForUser("trip-1"));
  });
});

describe("listTripsForUser", () => {
  it("queries owner-or-confirmed-collaborator trips ordered by start date", async () => {
    vi.mocked(prisma.trip.findMany).mockResolvedValue([]);
    await listTripsForUser("user-1");
    expect(prisma.trip.findMany).toHaveBeenCalledWith({
      where: {
        OR: [
          { ownerId: "user-1" },
          { collaborators: { some: { userId: "user-1", status: "confirmed" } } },
        ],
      },
      orderBy: { startDate: "asc" },
    });
  });
});

describe("getActiveTripId", () => {
  const today = new Date();
  const utcToday = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()));
  const daysFromToday = (n: number) => new Date(utcToday.getTime() + n * 86_400_000);

  it("returns null when the user has no trips", async () => {
    vi.mocked(prisma.trip.findMany).mockResolvedValue([]);
    await expect(getActiveTripId("user-1")).resolves.toBeNull();
  });

  it("prefers an ongoing trip (today within start-end) over upcoming/past", async () => {
    vi.mocked(prisma.trip.findMany).mockResolvedValue([
      trip({ id: "past", startDate: daysFromToday(-10), endDate: daysFromToday(-5) }),
      trip({ id: "ongoing", startDate: daysFromToday(-1), endDate: daysFromToday(2) }),
      trip({ id: "upcoming", startDate: daysFromToday(5), endDate: daysFromToday(8) }),
    ]);
    await expect(getActiveTripId("user-1")).resolves.toBe("ongoing");
  });

  it("falls back to the nearest upcoming trip when nothing is ongoing", async () => {
    vi.mocked(prisma.trip.findMany).mockResolvedValue([
      trip({ id: "far-upcoming", startDate: daysFromToday(20), endDate: daysFromToday(25) }),
      trip({ id: "near-upcoming", startDate: daysFromToday(3), endDate: daysFromToday(6) }),
      trip({ id: "past", startDate: daysFromToday(-10), endDate: daysFromToday(-5) }),
    ]);
    await expect(getActiveTripId("user-1")).resolves.toBe("near-upcoming");
  });

  it("falls back to the most recently ended past trip when nothing is ongoing or upcoming", async () => {
    vi.mocked(prisma.trip.findMany).mockResolvedValue([
      trip({ id: "older-past", startDate: daysFromToday(-30), endDate: daysFromToday(-25) }),
      trip({ id: "recent-past", startDate: daysFromToday(-10), endDate: daysFromToday(-5) }),
    ]);
    await expect(getActiveTripId("user-1")).resolves.toBe("recent-past");
  });
});
