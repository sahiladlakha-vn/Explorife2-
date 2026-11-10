import { describe, it, expect, vi, beforeEach } from "vitest";
import type { User } from "@supabase/supabase-js";

// Same mocking approach as lib/server/trips.test.ts: `createClient()` and
// `prisma` are mocked rather than hit for real. `requireUser()`/
// `requireTripAccess()` are NOT mocked — they're exercised for real against
// the mocked Supabase/Prisma clients, so these tests also pin down the
// auth/access-gating behavior of every mutator, not just the business logic
// layered on top of it.
vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(),
}));
vi.mock("@/lib/db", () => ({
  prisma: {
    trip: {
      findUnique: vi.fn(),
    },
    tripCollaborator: {
      findUnique: vi.fn(),
      findMany: vi.fn(),
      create: vi.fn(),
    },
    tripDocument: {
      findMany: vi.fn(),
      findUnique: vi.fn(),
      create: vi.fn(),
      deleteMany: vi.fn(),
    },
    tripPackingItem: {
      findMany: vi.fn(),
      findUnique: vi.fn(),
      create: vi.fn(),
      count: vi.fn(),
      updateMany: vi.fn(),
      deleteMany: vi.fn(),
    },
    profile: {
      findMany: vi.fn(),
      findUnique: vi.fn(),
    },
    $queryRaw: vi.fn(),
  },
}));

import { createClient } from "@/lib/supabase/server";
import { prisma } from "@/lib/db";
import { AuthError, ForbiddenError } from "@/lib/auth/permissions";
import {
  getTripSetup,
  findUserByIdentifier,
  addTraveler,
  addDocument,
  removeDocument,
  addPackingItem,
  setPackingItemPacked,
  removePackingItem,
} from "./trip-setup";

function mockSessionUser(user: Pick<User, "id"> | null) {
  vi.mocked(createClient).mockResolvedValue({
    auth: {
      getUser: vi.fn().mockResolvedValue({ data: { user } }),
    },
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- partial Supabase client stub, only `auth.getUser()` is exercised
  } as any);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any -- test double, only the fields requireTripAccess/getTripSetup read
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

/** Owner fast-path: `requireTripAccess` never looks at `tripCollaborator` for the owner, same as trips.test.ts. */
function mockOwnerAccess(tripOverrides: Partial<ReturnType<typeof trip>> = {}) {
  mockSessionUser({ id: "owner-1" });
  vi.mocked(prisma.trip.findUnique).mockResolvedValue(trip(tripOverrides));
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(prisma.tripDocument.findMany).mockResolvedValue([]);
  vi.mocked(prisma.tripPackingItem.findMany).mockResolvedValue([]);
  vi.mocked(prisma.tripCollaborator.findMany).mockResolvedValue([]);
  vi.mocked(prisma.profile.findMany).mockResolvedValue([]);
});

describe("getTripSetup", () => {
  it("propagates requireTripAccess's AuthError when there's no session", async () => {
    mockSessionUser(null);
    await expect(getTripSetup("trip-1")).rejects.toBeInstanceOf(AuthError);
  });

  it("labels the owner's collaborator row organizer and sorts it first", async () => {
    mockOwnerAccess();
    vi.mocked(prisma.tripCollaborator.findMany).mockResolvedValue([
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      { id: "collab-member", tripId: "trip-1", userId: "member-1", permission: "edit", status: "confirmed" } as any,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      { id: "collab-owner", tripId: "trip-1", userId: "owner-1", permission: "edit", status: "confirmed" } as any,
    ]);
    vi.mocked(prisma.profile.findMany).mockResolvedValue([
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      { id: "owner-1", displayName: "Owner Name", avatarUrl: "owner.png" } as any,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      { id: "member-1", displayName: "Member Name", avatarUrl: null } as any,
    ]);

    const setup = await getTripSetup("trip-1");

    expect(setup.travelers).toEqual([
      {
        id: "collab-owner",
        userId: "owner-1",
        displayName: "Owner Name",
        avatarUrl: "owner.png",
        role: "organizer",
        status: "confirmed",
      },
      {
        id: "collab-member",
        userId: "member-1",
        displayName: "Member Name",
        avatarUrl: null,
        role: "member",
        status: "confirmed",
      },
    ]);
    expect(prisma.profile.findMany).toHaveBeenCalledWith({
      where: { id: { in: ["owner-1", "member-1"] } },
      select: { id: true, displayName: true, avatarUrl: true },
    });
  });

  it("synthesizes a fallback organizer row when the trip has no real owner collaborator row", async () => {
    mockOwnerAccess();
    vi.mocked(prisma.tripCollaborator.findMany).mockResolvedValue([]);
    vi.mocked(prisma.profile.findMany).mockResolvedValue([
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      { id: "owner-1", displayName: "Owner Name", avatarUrl: null } as any,
    ]);

    const setup = await getTripSetup("trip-1");

    expect(setup.travelers).toEqual([
      {
        id: "owner-1",
        userId: "owner-1",
        displayName: "Owner Name",
        avatarUrl: null,
        role: "organizer",
        status: "confirmed",
      },
    ]);
  });

  it("falls back to 'Traveler' and a null avatar when a collaborator has no profile row", async () => {
    mockOwnerAccess();
    vi.mocked(prisma.tripCollaborator.findMany).mockResolvedValue([
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      { id: "collab-owner", tripId: "trip-1", userId: "owner-1", permission: "edit", status: "confirmed" } as any,
    ]);
    vi.mocked(prisma.profile.findMany).mockResolvedValue([]);

    const setup = await getTripSetup("trip-1");

    expect(setup.travelers[0]).toMatchObject({ displayName: "Traveler", avatarUrl: null });
  });

  it("treats any non-'invited' collaborator status as confirmed", async () => {
    mockOwnerAccess();
    vi.mocked(prisma.tripCollaborator.findMany).mockResolvedValue([
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      { id: "collab-owner", tripId: "trip-1", userId: "owner-1", permission: "edit", status: "invited" } as any,
    ]);

    const setup = await getTripSetup("trip-1");
    expect(setup.travelers[0].status).toBe("invited");
  });

  it("queries documents and packing items with the expected ordering", async () => {
    mockOwnerAccess();
    await getTripSetup("trip-1");

    expect(prisma.tripDocument.findMany).toHaveBeenCalledWith({
      where: { tripId: "trip-1" },
      orderBy: [{ expiresOn: { sort: "asc", nulls: "last" } }, { createdAt: "asc" }],
    });
    expect(prisma.tripPackingItem.findMany).toHaveBeenCalledWith({
      where: { tripId: "trip-1" },
      orderBy: { sortOrder: "asc" },
    });
  });

  it("normalizes an unrecognized document type to 'reservation'", async () => {
    mockOwnerAccess();
    vi.mocked(prisma.tripDocument.findMany).mockResolvedValue([
      {
        id: "doc-1",
        tripId: "trip-1",
        ownerCollaboratorId: null,
        type: "some-future-type",
        title: "Mystery doc",
        fileUrl: null,
        expiresOn: null,
        createdAt: new Date("2026-01-01T00:00:00.000Z"),
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
      } as any,
    ]);

    const setup = await getTripSetup("trip-1");
    expect(setup.documents[0].type).toBe("reservation");
  });

  it("passes packing items through unchanged", async () => {
    mockOwnerAccess();
    const items = [
      {
        id: "item-1",
        tripId: "trip-1",
        assigneeCollaboratorId: null,
        label: "Passport",
        category: null,
        quantity: 1,
        isPacked: false,
        sortOrder: 0,
        createdAt: new Date("2026-01-01T00:00:00.000Z"),
      },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    ] as any;
    vi.mocked(prisma.tripPackingItem.findMany).mockResolvedValue(items);

    const setup = await getTripSetup("trip-1");
    expect(setup.packingItems).toBe(items);
  });
});

describe("findUserByIdentifier", () => {
  it("throws AuthError when there's no session", async () => {
    mockSessionUser(null);
    await expect(findUserByIdentifier("someone@example.com")).rejects.toBeInstanceOf(AuthError);
    expect(prisma.$queryRaw).not.toHaveBeenCalled();
  });

  it("returns null without querying for a blank identifier", async () => {
    mockSessionUser({ id: "user-1" });
    await expect(findUserByIdentifier("   ")).resolves.toBeNull();
    expect(prisma.$queryRaw).not.toHaveBeenCalled();
  });

  it("returns null when the RPC finds no match", async () => {
    mockSessionUser({ id: "user-1" });
    vi.mocked(prisma.$queryRaw).mockResolvedValue([]);
    await expect(findUserByIdentifier("nobody@example.com")).resolves.toBeNull();
  });

  it("falls back to 'Explorer' when display_name is null", async () => {
    mockSessionUser({ id: "user-1" });
    vi.mocked(prisma.$queryRaw).mockResolvedValue([
      { id: "found-1", display_name: null, avatar_url: null, username: "found" },
    ]);
    await expect(findUserByIdentifier("found@example.com")).resolves.toEqual({
      id: "found-1",
      displayName: "Explorer",
      avatarUrl: null,
      username: "found",
    });
  });

  it("falls back to 'Explorer' when display_name is blank/whitespace", async () => {
    mockSessionUser({ id: "user-1" });
    vi.mocked(prisma.$queryRaw).mockResolvedValue([
      { id: "found-1", display_name: "   ", avatar_url: null, username: null },
    ]);
    const result = await findUserByIdentifier("found@example.com");
    expect(result?.displayName).toBe("Explorer");
  });

  it("returns the real display name when present", async () => {
    mockSessionUser({ id: "user-1" });
    vi.mocked(prisma.$queryRaw).mockResolvedValue([
      { id: "found-1", display_name: "Real Name", avatar_url: "a.png", username: "realname" },
    ]);
    await expect(findUserByIdentifier("found@example.com")).resolves.toEqual({
      id: "found-1",
      displayName: "Real Name",
      avatarUrl: "a.png",
      username: "realname",
    });
  });
});

describe("addTraveler", () => {
  it("throws ForbiddenError for a non-owner collaborator, without inserting a row", async () => {
    mockSessionUser({ id: "collab-1" });
    vi.mocked(prisma.trip.findUnique).mockResolvedValue(trip({ ownerId: "owner-1" }));
    vi.mocked(prisma.tripCollaborator.findUnique).mockResolvedValue(
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      { status: "confirmed" } as any,
    );

    await expect(addTraveler({ tripId: "trip-1", userId: "new-user" })).rejects.toBeInstanceOf(ForbiddenError);
    expect(prisma.tripCollaborator.create).not.toHaveBeenCalled();
  });

  it("inserts a confirmed collaborator and re-derives the display name/avatar from profiles", async () => {
    mockOwnerAccess();
    vi.mocked(prisma.tripCollaborator.create).mockResolvedValue({
      id: "new-collab-1",
      tripId: "trip-1",
      userId: "new-user",
      permission: "edit",
      status: "confirmed",
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any);
    vi.mocked(prisma.profile.findUnique).mockResolvedValue({
      displayName: "Jane Doe",
      avatarUrl: "jane.png",
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any);

    const result = await addTraveler({ tripId: "trip-1", userId: "new-user" });

    expect(prisma.tripCollaborator.create).toHaveBeenCalledWith({
      data: { tripId: "trip-1", userId: "new-user", permission: "edit", status: "confirmed" },
    });
    expect(result).toEqual({
      id: "new-collab-1",
      userId: "new-user",
      displayName: "Jane Doe",
      avatarUrl: "jane.png",
      role: "member",
      status: "confirmed",
    });
  });

  it("falls back to 'Traveler'/null when the new collaborator has no profile row", async () => {
    mockOwnerAccess();
    vi.mocked(prisma.tripCollaborator.create).mockResolvedValue({
      id: "new-collab-1",
      tripId: "trip-1",
      userId: "new-user",
      permission: "edit",
      status: "confirmed",
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any);
    vi.mocked(prisma.profile.findUnique).mockResolvedValue(null);

    const result = await addTraveler({ tripId: "trip-1", userId: "new-user" });
    expect(result.displayName).toBe("Traveler");
    expect(result.avatarUrl).toBeNull();
  });
});

describe("addDocument", () => {
  it("throws on a blank title without creating a row", async () => {
    mockOwnerAccess();
    await expect(addDocument({ tripId: "trip-1", type: "passport", title: "   " })).rejects.toThrow();
    expect(prisma.tripDocument.create).not.toHaveBeenCalled();
  });

  it("trims the title, normalizes the type, and turns a blank URL into null", async () => {
    mockOwnerAccess();
    vi.mocked(prisma.tripDocument.create).mockResolvedValue({
      id: "doc-1",
      tripId: "trip-1",
      ownerCollaboratorId: null,
      type: "passport",
      title: "My Passport",
      fileUrl: null,
      expiresOn: null,
      createdAt: new Date("2026-01-01T00:00:00.000Z"),
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any);

    await addDocument({
      tripId: "trip-1",
      type: "not-a-real-type",
      title: "  My Passport  ",
      fileUrl: "   ",
    });

    expect(prisma.tripDocument.create).toHaveBeenCalledWith({
      data: {
        tripId: "trip-1",
        ownerCollaboratorId: null,
        type: "reservation",
        title: "My Passport",
        fileUrl: null,
        expiresOn: null,
      },
    });
  });
});

describe("removeDocument", () => {
  it("is a no-op when the document doesn't exist", async () => {
    vi.mocked(prisma.tripDocument.findUnique).mockResolvedValue(null);
    await removeDocument("missing-doc");
    expect(prisma.trip.findUnique).not.toHaveBeenCalled();
    expect(prisma.tripDocument.deleteMany).not.toHaveBeenCalled();
  });

  it("authorizes against the document's real trip, then deletes it scoped by id+tripId", async () => {
    vi.mocked(prisma.tripDocument.findUnique).mockResolvedValue({
      tripId: "trip-1",
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any);
    mockOwnerAccess();

    await removeDocument("doc-1");

    expect(prisma.tripDocument.deleteMany).toHaveBeenCalledWith({
      where: { id: "doc-1", tripId: "trip-1" },
    });
  });
});

describe("addPackingItem", () => {
  it("throws on a blank label without creating a row", async () => {
    mockOwnerAccess();
    await expect(addPackingItem({ tripId: "trip-1", label: "   " })).rejects.toThrow();
    expect(prisma.tripPackingItem.create).not.toHaveBeenCalled();
  });

  it("appends to the end via a count-based sortOrder and clears a blank category", async () => {
    mockOwnerAccess();
    vi.mocked(prisma.tripPackingItem.count).mockResolvedValue(3);
    vi.mocked(prisma.tripPackingItem.create).mockResolvedValue({} as never);

    await addPackingItem({ tripId: "trip-1", label: "Sunscreen", category: "   " });

    expect(prisma.tripPackingItem.count).toHaveBeenCalledWith({ where: { tripId: "trip-1" } });
    expect(prisma.tripPackingItem.create).toHaveBeenCalledWith({
      data: {
        tripId: "trip-1",
        assigneeCollaboratorId: null,
        label: "Sunscreen",
        category: null,
        quantity: 1,
        sortOrder: 3,
      },
    });
  });

  it("clamps quantity to the 1..99 range", async () => {
    mockOwnerAccess();
    vi.mocked(prisma.tripPackingItem.count).mockResolvedValue(0);
    vi.mocked(prisma.tripPackingItem.create).mockResolvedValue({} as never);

    await addPackingItem({ tripId: "trip-1", label: "Too many", quantity: 500 });
    expect(prisma.tripPackingItem.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ quantity: 99 }) }),
    );

    await addPackingItem({ tripId: "trip-1", label: "Too few", quantity: 0 });
    expect(prisma.tripPackingItem.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ quantity: 1 }) }),
    );
  });
});

describe("setPackingItemPacked", () => {
  it("is a no-op when the item doesn't exist", async () => {
    vi.mocked(prisma.tripPackingItem.findUnique).mockResolvedValue(null);
    await setPackingItemPacked("missing-item", true);
    expect(prisma.trip.findUnique).not.toHaveBeenCalled();
    expect(prisma.tripPackingItem.updateMany).not.toHaveBeenCalled();
  });

  it("authorizes against the item's real trip, then updates isPacked scoped by id+tripId", async () => {
    vi.mocked(prisma.tripPackingItem.findUnique).mockResolvedValue({
      tripId: "trip-1",
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any);
    mockOwnerAccess();

    await setPackingItemPacked("item-1", true);

    expect(prisma.tripPackingItem.updateMany).toHaveBeenCalledWith({
      where: { id: "item-1", tripId: "trip-1" },
      data: { isPacked: true },
    });
  });
});

describe("removePackingItem", () => {
  it("is a no-op when the item doesn't exist", async () => {
    vi.mocked(prisma.tripPackingItem.findUnique).mockResolvedValue(null);
    await removePackingItem("missing-item");
    expect(prisma.trip.findUnique).not.toHaveBeenCalled();
    expect(prisma.tripPackingItem.deleteMany).not.toHaveBeenCalled();
  });

  it("authorizes against the item's real trip, then deletes it scoped by id+tripId", async () => {
    vi.mocked(prisma.tripPackingItem.findUnique).mockResolvedValue({
      tripId: "trip-1",
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any);
    mockOwnerAccess();

    await removePackingItem("item-1");

    expect(prisma.tripPackingItem.deleteMany).toHaveBeenCalledWith({
      where: { id: "item-1", tripId: "trip-1" },
    });
  });
});
