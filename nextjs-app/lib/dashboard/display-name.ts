/**
 * Name shown in "Welcome back, …": the profile's display name, else its plain
 * name, else nothing (the header then just says "Welcome back"). Never falls
 * back to the e-mail address.
 */
export function pickDisplayName(
  profile: { displayName: string | null; name: string | null } | null,
): string | null {
  if (!profile) return null;
  return profile.displayName?.trim() || profile.name?.trim() || null;
}
