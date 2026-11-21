import "server-only";
import { prisma } from "@/lib/db";
import { pickDisplayName } from "@/lib/dashboard/display-name";

/**
 * The signed-in admin's name for the dashboard greeting. Deliberately NOT in
 * lib/server/admin-dashboard.ts: that file is `"use cache"` and shared by every
 * admin, while this is per-user, so it must stay uncached. Reads only
 * `displayName`/`name` — never the e-mail address or phone.
 */
export async function getAdminDisplayName(
  userId: string,
): Promise<string | null> {
  const profile = await prisma.profile.findUnique({
    where: { id: userId },
    select: { displayName: true, name: true },
  });
  return pickDisplayName(profile);
}
