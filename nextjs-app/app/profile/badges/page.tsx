/**
 * `instant = false` — see `app/profile/overview/page.tsx`'s comment:
 * `ProfileLayoutBody` withholds `{children}` (this page) when there's no
 * session/profile, which is the documented "slot gated by authentication"
 * case for this fix rather than rendering the dropped segment.
 */
export const instant = false;

export default function BadgesPage() {
  return (
    <div className="px-4 py-6 md:px-6 lg:px-8">
      <p className="text-text-muted">Badges tab — content lands in a later step.</p>
    </div>
  );
}
