import "server-only";
import { redirect } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { ADMIN_ROLES, getCurrentUser, getUserRole, type Role } from "./permissions";
import { sanitizeRedirect } from "./redirect";

/**
 * For Server Components whose entire page requires a REAL (non-guest)
 * account — redirects to `/auth?redirect=<currentPath>` rather than
 * throwing, since "please sign in" isn't the kind of unexpected failure
 * `error.tsx` boundaries are for. `requireUser`/`requireRealUser` in
 * `./permissions` stay throw-based for Server Actions/Route Handlers, where
 * a thrown error is the correct shape.
 *
 * `currentPath` should be the page's own path (e.g. the literal segment
 * path, optionally with its query string) so sign-in lands the visitor back
 * where they started; it's run through `sanitizeRedirect` regardless, so a
 * caller can never accidentally construct an open redirect here either.
 */
export async function requireRealUserOrRedirect(currentPath: string): Promise<User> {
  const user = await getCurrentUser();
  if (!user || user.is_anonymous) {
    redirect(`/auth?redirect=${encodeURIComponent(sanitizeRedirect(currentPath))}`);
  }
  return user;
}

/**
 * Page-level counterpart to `requireAdmin()` (`./permissions`): same
 * `ADMIN_ROLES` check, but redirects instead of throwing, matching
 * `requireRealUserOrRedirect`'s reasoning above — an unauthenticated or
 * non-admin visitor hitting an admin page isn't an `error.tsx`-worthy
 * failure. No session (or a guest session) redirects to sign-in like
 * `requireRealUserOrRedirect`; a signed-in non-admin redirects to `/profile`
 * instead, since `/auth` would be confusing for an already-authenticated user.
 */
export async function requireAdminOrRedirect(currentPath: string): Promise<{ user: User; role: Role }> {
  const user = await requireRealUserOrRedirect(currentPath);
  const role = await getUserRole(user.id);
  if (!role || !ADMIN_ROLES.includes(role)) {
    redirect("/profile");
  }
  return { user, role };
}
