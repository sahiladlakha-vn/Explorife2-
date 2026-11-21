import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/lib/db", () => ({
  prisma: {
    profile: {
      findUnique: vi.fn(),
    },
  },
}));

import { prisma } from "@/lib/db";
import { getAdminDisplayName } from "./admin-profile";

beforeEach(() => {
  vi.resetAllMocks();
});

function mockProfile(profile: { displayName: string | null; name: string | null } | null) {
  vi.mocked(prisma.profile.findUnique).mockResolvedValue(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- only the selected fields are read
    profile as any,
  );
}

describe("getAdminDisplayName", () => {
  it("prefers the display name", async () => {
    mockProfile({ displayName: "Linh", name: "Nguyen Thi Linh" });
    await expect(getAdminDisplayName("user-1")).resolves.toBe("Linh");
  });

  it("falls back to the plain name when there is no display name", async () => {
    mockProfile({ displayName: null, name: "Nguyen Thi Linh" });
    await expect(getAdminDisplayName("user-1")).resolves.toBe("Nguyen Thi Linh");
  });

  it("returns null when the profile has neither, or does not exist", async () => {
    mockProfile({ displayName: null, name: null });
    await expect(getAdminDisplayName("user-1")).resolves.toBeNull();

    mockProfile(null);
    await expect(getAdminDisplayName("user-2")).resolves.toBeNull();
  });

  it("reads only the two name columns — never the e-mail address or phone", async () => {
    mockProfile({ displayName: "Linh", name: null });
    await getAdminDisplayName("user-1");
    expect(prisma.profile.findUnique).toHaveBeenCalledWith({
      where: { id: "user-1" },
      select: { displayName: true, name: true },
    });
  });
});
