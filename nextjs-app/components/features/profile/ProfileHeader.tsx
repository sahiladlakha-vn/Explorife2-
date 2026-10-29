import type { Profile, Leaderboard } from "@/lib/generated/prisma/client";

function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  return parts
    .slice(0, 2)
    .map((p) => p[0]!.toUpperCase())
    .join("");
}

function roleLabel(role: string): string {
  return role
    .split("_")
    .map((w) => w[0]!.toUpperCase() + w.slice(1))
    .join(" ");
}

interface Stat {
  label: string;
  value: number;
}

export function ProfileHeader({
  profile,
  leaderboardEntry,
}: {
  profile: Profile;
  leaderboardEntry: Leaderboard | null;
}) {
  const displayName = profile.displayName || profile.name || "Traveler";
  const stats: Stat[] = [
    { label: "Gems found", value: leaderboardEntry?.gemsDiscovered ?? 0 },
    { label: "Stories", value: leaderboardEntry?.journalsWritten ?? 0 },
    { label: "Countries", value: leaderboardEntry?.countriesVisited ?? 0 },
  ];

  return (
    <div className="flex flex-col gap-4 px-4 py-6 md:flex-row md:items-center md:gap-6 md:px-6 lg:px-8">
      <div className="bg-surface-raised text-text flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden rounded-full text-xl font-semibold">
        {profile.avatarUrl ? (
          // eslint-disable-next-line @next/next/no-img-element -- avatar source is arbitrary user-supplied storage URL, not a static/local asset
          <img src={profile.avatarUrl} alt="" className="h-full w-full object-cover" />
        ) : (
          initials(displayName)
        )}
      </div>

      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-text truncate text-xl font-semibold">{displayName}</h1>
          <span className="bg-surface-raised text-text-muted rounded-full px-2.5 py-0.5 text-xs font-medium">
            {roleLabel(profile.role)}
          </span>
        </div>
        <dl className="mt-3 flex gap-6">
          {stats.map((stat) => (
            <div key={stat.label}>
              <dt className="text-text-muted text-xs">{stat.label}</dt>
              <dd className="text-text text-lg font-semibold">{stat.value}</dd>
            </div>
          ))}
        </dl>
      </div>
    </div>
  );
}
