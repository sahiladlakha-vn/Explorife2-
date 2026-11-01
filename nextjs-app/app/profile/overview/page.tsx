/**
 * `instant = false`, not a render-the-segment fix: `ProfileLayoutBody`
 * (`components/features/profile/ProfileLayoutBody.tsx`) withholds
 * `{children}` entirely — not just the header/tabs — when there's no
 * session or no profile row, so this page is a dropped segment in that
 * state and Next 16's instant-navigation validation flags it (docs:
 * https://nextjs.org/docs/messages/instant-unrendered-segment). The docs'
 * own example for choosing `instant = false` over "render the dropped
 * segment" is "a slot gated by authentication" — exactly this case.
 * Rendering the segment instead would mean duplicating the guest/no-profile
 * sign-in prompt in every `/profile/*` leaf page instead of once in the
 * shared layout body.
 */
export const instant = false;

export default function OverviewPage() {
  return (
    <div className="px-4 py-6 md:px-6 lg:px-8">
      <p className="text-text-muted">Overview tab — content lands in a later step.</p>
    </div>
  );
}
