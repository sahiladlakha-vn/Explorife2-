"use server";

import {
  findUserByIdentifier,
  addTraveler,
  addDocument,
  removeDocument,
  addPackingItem,
  setPackingItemPacked,
  removePackingItem,
  type TripTraveler,
  type TripDocumentView,
  type PublicProfileLookup,
} from "@/lib/server/trip-setup";
import type { TripPackingItem } from "@/lib/generated/prisma/client";

/**
 * Thin "use server" call boundary around lib/server/trip-setup.ts — the
 * first client-triggered mutation feature in this port, so this file
 * establishes the convention: a `server-only` data/authorization module
 * (trip-setup.ts) paired with a sibling "use server" actions module of real
 * function definitions (not bare re-exports — Next's compiler needs to see
 * an actual function body at this boundary to create a server action
 * reference). Mirrors the existing split between lib/auth/permissions.ts
 * (server-only) and lib/auth/actions.ts ("use server").
 *
 * Every function here is a plain typed-argument async function, callable
 * directly from a Client Component (e.g. inside startTransition) rather than
 * only via a literal `<form action={...}>` — same directly-callable pattern
 * `signInWithProvider` already establishes in lib/auth/actions.ts.
 */

export async function findUserByIdentifierAction(identifier: string): Promise<PublicProfileLookup | null> {
  return findUserByIdentifier(identifier);
}

export async function addTravelerAction(params: { tripId: string; userId: string }): Promise<TripTraveler> {
  return addTraveler(params);
}

export async function addDocumentAction(params: {
  tripId: string;
  ownerCollaboratorId?: string | null;
  type: string;
  title: string;
  fileUrl?: string | null;
  expiresOn?: Date | null;
}): Promise<TripDocumentView> {
  return addDocument(params);
}

export async function removeDocumentAction(documentId: string): Promise<void> {
  await removeDocument(documentId);
}

export async function addPackingItemAction(params: {
  tripId: string;
  assigneeCollaboratorId?: string | null;
  label: string;
  category?: string | null;
  quantity?: number;
}): Promise<TripPackingItem> {
  return addPackingItem(params);
}

export async function setPackingItemPackedAction(itemId: string, isPacked: boolean): Promise<void> {
  await setPackingItemPacked(itemId, isPacked);
}

export async function removePackingItemAction(itemId: string): Promise<void> {
  await removePackingItem(itemId);
}
