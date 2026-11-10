import "server-only";
import { cache } from "react";
import { prisma } from "@/lib/db";
import { requireUser, ForbiddenError } from "@/lib/auth/permissions";
import { requireTripAccess } from "@/lib/server/trips";
import { type DocumentType, normalizeDocumentType } from "@/lib/trips/document-type";
import type { TripPackingItem } from "@/lib/generated/prisma/client";

/**
 * Step 4 Trip-screen data/mutation layer (MIGRATION_PLAN.md §7 Step 4 /
 * Batch 1) — ports `trip_setup_provider.dart`'s `TripSetupProvider`. Prisma
 * bypasses RLS, so every read/write here re-implements, in code, the
 * authorization the live Postgres policies used to provide:
 *   - `trip_collaborators_insert_by_owner` (owner-only INSERT) -> `addTraveler`
 *     throws `ForbiddenError` for a non-owner caller.
 *   - `trip_documents_via_trip` / `trip_packing_items_via_trip` (owner OR a
 *     collaborator with `permission = 'edit'`, FOR ALL) -> every document/
 *     packing mutator calls `requireTripAccess`, which only distinguishes
 *     owner-or-confirmed-collaborator. This collapses the policies' finer
 *     `permission = 'edit'` condition, which is fine today because every
 *     insert path in this module (and in the Dart app) hardcodes
 *     `permission: 'edit'` — there is no live `'view'`-only collaborator for
 *     the distinction to matter for yet.
 *
 * `getTripSetup` is wrapped in React's `cache()` so a trip page and any
 * sibling segment reading the same trip's setup within one request share a
 * single round-trip — same reasoning as `requireTripAccess` in
 * `lib/server/trips.ts`. This is a within-request dedupe only, not a
 * correctness-affecting cache across requests/mutations.
 */

export type TravelerRole = "organizer" | "member";
export type TravelerStatus = "confirmed" | "invited";

/** View model assembled by `getTripSetup` — not a 1:1 table row (joins `trip_collaborators` against `profiles`). Mirrors `TripTraveler` (trip_traveler.dart). */
export interface TripTraveler {
  id: string;
  userId: string;
  displayName: string;
  avatarUrl: string | null;
  role: TravelerRole;
  status: TravelerStatus;
}

/** `trip_documents` row, with `type` narrowed from Prisma's plain `string` to the `DocumentType` union. */
export interface TripDocumentView {
  id: string;
  tripId: string;
  ownerCollaboratorId: string | null;
  type: DocumentType;
  title: string;
  fileUrl: string | null;
  expiresOn: Date | null;
  createdAt: Date;
}

export interface TripSetup {
  travelers: TripTraveler[];
  documents: TripDocumentView[];
  packingItems: TripPackingItem[];
}

/** Mirrors `PublicProfile` (as surfaced by the `find_user_by_identifier` RPC) — used by the "Add Traveler" lookup sheet. */
export interface PublicProfileLookup {
  id: string;
  displayName: string;
  avatarUrl: string | null;
  username: string | null;
}

async function profileNamesById(
  userIds: string[],
): Promise<Map<string, { displayName: string | null; avatarUrl: string | null }>> {
  if (userIds.length === 0) return new Map();
  const rows = await prisma.profile.findMany({
    where: { id: { in: userIds } },
    select: { id: true, displayName: true, avatarUrl: true },
  });
  return new Map(rows.map((row) => [row.id, { displayName: row.displayName, avatarUrl: row.avatarUrl }]));
}

/**
 * Throws/redirects via `requireTripAccess` (no session -> `AuthError`; no
 * access -> `notFound()`). Fetches documents/packing items/collaborators in
 * parallel, then a second `profiles` query for the union of
 * `{ownerId, ...collaborator userIds}` — same two-phase shape as
 * `loadSetup`, since the ids to look up aren't known until the first query
 * returns.
 */
export const getTripSetup = cache(async function getTripSetup(tripId: string): Promise<TripSetup> {
  const { trip } = await requireTripAccess(tripId);

  const [documentRows, packingItems, collaborators] = await Promise.all([
    prisma.tripDocument.findMany({
      where: { tripId },
      orderBy: [{ expiresOn: { sort: "asc", nulls: "last" } }, { createdAt: "asc" }],
    }),
    prisma.tripPackingItem.findMany({
      where: { tripId },
      orderBy: { sortOrder: "asc" },
    }),
    prisma.tripCollaborator.findMany({ where: { tripId } }),
  ]);

  const userIds = Array.from(new Set([trip.ownerId, ...collaborators.map((row) => row.userId)]));
  const profiles = await profileNamesById(userIds);

  // Null-only fallback (blank strings pass through unchanged) — distinct
  // from findUserByIdentifier's null-OR-blank "Explorer" fallback below;
  // both are deliberate, separate behaviors ported as-is from the Dart app.
  const nameFor = (userId: string) => profiles.get(userId)?.displayName ?? "Traveler";
  const avatarFor = (userId: string) => profiles.get(userId)?.avatarUrl ?? null;

  const hasOwnerRow = collaborators.some((row) => row.userId === trip.ownerId);
  const travelers: TripTraveler[] = collaborators.map((row) => ({
    id: row.id,
    userId: row.userId,
    displayName: nameFor(row.userId),
    avatarUrl: avatarFor(row.userId),
    role: row.userId === trip.ownerId ? "organizer" : "member",
    status: row.status === "invited" ? "invited" : "confirmed",
  }));
  if (!hasOwnerRow) {
    // Defensive fallback for a trip predating both the owner-collaborator
    // backfill migration and createTrip's own insert — keeps the organizer
    // visible even without a real row. This synthesized row's `id` isn't a
    // real trip_collaborators.id, so it can't be used as a document-owner/
    // packing-assignee FK target — an acceptable gap for a
    // not-yet-backfilled trip, not the common case.
    travelers.push({
      id: trip.ownerId,
      userId: trip.ownerId,
      displayName: nameFor(trip.ownerId),
      avatarUrl: avatarFor(trip.ownerId),
      role: "organizer",
      status: "confirmed",
    });
  }
  // Organizer always leads, regardless of row insertion order. Array#sort
  // has been a stable sort in every evergreen JS engine since 2019, so ties
  // among members keep their collaborator-row order.
  travelers.sort((a, b) => (a.role === b.role ? 0 : a.role === "organizer" ? -1 : 1));

  const documents: TripDocumentView[] = documentRows.map((doc) => ({
    id: doc.id,
    tripId: doc.tripId,
    ownerCollaboratorId: doc.ownerCollaboratorId,
    type: normalizeDocumentType(doc.type),
    title: doc.title,
    fileUrl: doc.fileUrl,
    expiresOn: doc.expiresOn,
    createdAt: doc.createdAt,
  }));

  return { travelers, documents, packingItems };
});

interface FindUserByIdentifierRow {
  id: string;
  display_name: string | null;
  avatar_url: string | null;
  username: string | null;
}

/**
 * Ports `AuthProvider.findUserByIdentifier` (auth_provider.dart) — calls the
 * live `find_user_by_identifier` SECURITY DEFINER RPC (exact-match only on
 * username/email, joins `auth.users`) via a raw query rather than
 * reimplementing its lookup, preserving "app code never touches
 * `auth.users.email` directly." Requires a session (the lookup sheet only
 * ever renders inside the authenticated app shell) but not trip access — the
 * caller doesn't know which trip (if any) the result will be added to yet.
 */
export async function findUserByIdentifier(identifier: string): Promise<PublicProfileLookup | null> {
  await requireUser();
  const trimmed = identifier.trim();
  if (trimmed.length === 0) return null;

  const rows = await prisma.$queryRaw<
    FindUserByIdentifierRow[]
  >`SELECT * FROM find_user_by_identifier(${trimmed})`;
  const row = rows[0];
  if (!row) return null;

  // Null-OR-blank check (distinct from getTripSetup's null-only "Traveler"
  // fallback above) with its own fallback word — mirrors
  // AuthProvider.findUserByIdentifier exactly.
  const displayName = row.display_name?.trim() ? row.display_name : "Explorer";

  return {
    id: row.id,
    displayName,
    avatarUrl: row.avatar_url,
    username: row.username,
  };
}

/**
 * Inserts a real `trip_collaborators` row for `userId` and returns the
 * resulting `TripTraveler`. Mirrors `TripSetupProvider.addTraveler`, except
 * display name/avatar are re-read from `profiles` here rather than trusted
 * from the caller — `TravelerLookupSheet` already resolved them client-side,
 * but a Server Action is a real trust boundary (unlike Dart's in-process
 * call), so they're re-derived rather than accepted as input.
 *
 * Owner-only, mirroring the live `trip_collaborators_insert_by_owner` RLS
 * policy (`is_trip_owner`). The "+ Add Traveler" button has no client-side
 * gating in the Dart app either — any authorized viewer can tap it — so this
 * throw is what turns a non-owner's attempt into a no-op, same as RLS used
 * to. A duplicate `userId` for this trip fails on the `(tripId, userId)`
 * primary key, surfaced as a plain thrown error like any other failure.
 */
export async function addTraveler({
  tripId,
  userId,
  permission = "edit",
}: {
  tripId: string;
  userId: string;
  permission?: string;
}): Promise<TripTraveler> {
  const { user, trip } = await requireTripAccess(tripId);
  if (user.id !== trip.ownerId) {
    throw new ForbiddenError("Only the trip owner can add travelers.");
  }

  const collaborator = await prisma.tripCollaborator.create({
    data: { tripId, userId, permission, status: "confirmed" },
  });

  const profile = await prisma.profile.findUnique({
    where: { id: userId },
    select: { displayName: true, avatarUrl: true },
  });

  return {
    id: collaborator.id,
    userId,
    displayName: profile?.displayName ?? "Traveler",
    avatarUrl: profile?.avatarUrl ?? null,
    role: userId === trip.ownerId ? "organizer" : "member",
    status: collaborator.status === "invited" ? "invited" : "confirmed",
  };
}

/** Mirrors `TripSetupProvider.addDocument`. */
export async function addDocument({
  tripId,
  ownerCollaboratorId,
  type,
  title,
  fileUrl,
  expiresOn,
}: {
  tripId: string;
  ownerCollaboratorId?: string | null;
  type: string;
  title: string;
  fileUrl?: string | null;
  expiresOn?: Date | null;
}): Promise<TripDocumentView> {
  await requireTripAccess(tripId);

  const trimmedTitle = title.trim();
  if (trimmedTitle.length === 0) {
    throw new Error("Title is required.");
  }

  const doc = await prisma.tripDocument.create({
    data: {
      tripId,
      ownerCollaboratorId: ownerCollaboratorId ?? null,
      type: normalizeDocumentType(type),
      title: trimmedTitle,
      fileUrl: fileUrl?.trim() ? fileUrl.trim() : null,
      expiresOn: expiresOn ?? null,
    },
  });

  return {
    id: doc.id,
    tripId: doc.tripId,
    ownerCollaboratorId: doc.ownerCollaboratorId,
    type: normalizeDocumentType(doc.type),
    title: doc.title,
    fileUrl: doc.fileUrl,
    expiresOn: doc.expiresOn,
    createdAt: doc.createdAt,
  };
}

/**
 * No-op if the document doesn't exist (mirrors `TripSetupProvider
 * .removeDocument`'s own "not found locally -> return" shape). The owning
 * trip is looked up from the row itself rather than trusted from a caller-
 * supplied `tripId`, so authorization is always checked against the
 * document's real trip, never one a caller merely claims.
 */
export async function removeDocument(documentId: string): Promise<void> {
  const doc = await prisma.tripDocument.findUnique({
    where: { id: documentId },
    select: { tripId: true },
  });
  if (!doc) return;
  await requireTripAccess(doc.tripId);
  await prisma.tripDocument.deleteMany({ where: { id: documentId, tripId: doc.tripId } });
}

/** Mirrors `TripSetupProvider.addPackingItem` — `sortOrder` is append-to-end, same as the Dart provider's cache-length-based derivation. */
export async function addPackingItem({
  tripId,
  assigneeCollaboratorId,
  label,
  category,
  quantity = 1,
}: {
  tripId: string;
  assigneeCollaboratorId?: string | null;
  label: string;
  category?: string | null;
  quantity?: number;
}): Promise<TripPackingItem> {
  await requireTripAccess(tripId);

  const trimmedLabel = label.trim();
  if (trimmedLabel.length === 0) {
    throw new Error("Label is required.");
  }

  const sortOrder = await prisma.tripPackingItem.count({ where: { tripId } });

  return prisma.tripPackingItem.create({
    data: {
      tripId,
      assigneeCollaboratorId: assigneeCollaboratorId ?? null,
      label: trimmedLabel,
      category: category?.trim() ? category.trim() : null,
      // _AddPackingItemSheet's stepper clamps to 1..99 client-side; re-clamp
      // here too since a Server Action is callable directly, bypassing that UI.
      quantity: Math.min(Math.max(Math.trunc(quantity), 1), 99),
      sortOrder,
    },
  });
}

/**
 * Mirrors `TripSetupProvider.togglePacked`'s wire payload — an explicit
 * boolean, not a "toggle" instruction (the toggling itself happens
 * client-side, in the optimistic-update layer). No-op if the item doesn't
 * exist, same shape as `removeDocument`.
 */
export async function setPackingItemPacked(itemId: string, isPacked: boolean): Promise<void> {
  const item = await prisma.tripPackingItem.findUnique({
    where: { id: itemId },
    select: { tripId: true },
  });
  if (!item) return;
  await requireTripAccess(item.tripId);
  await prisma.tripPackingItem.updateMany({
    where: { id: itemId, tripId: item.tripId },
    data: { isPacked },
  });
}

/** Mirrors `TripSetupProvider.removePackingItem`. */
export async function removePackingItem(itemId: string): Promise<void> {
  const item = await prisma.tripPackingItem.findUnique({
    where: { id: itemId },
    select: { tripId: true },
  });
  if (!item) return;
  await requireTripAccess(item.tripId);
  await prisma.tripPackingItem.deleteMany({ where: { id: itemId, tripId: item.tripId } });
}
