/**
 * Full-bleed, softly blurred warm travel scene behind the dashboard with a
 * dark overlay so text on the glass stays readable. The scene is the
 * generated illustration in public/admin/dashboard-scene.svg (see
 * `.admin-dashboard-scene` in app/globals.css) — swap it for a real photo by
 * changing that one `url()`. Decorative: hidden from assistive tech.
 */
export function DashboardBackdrop() {
  return (
    <div
      aria-hidden="true"
      data-testid="dashboard-backdrop"
      className="fixed inset-0 -z-10 overflow-hidden bg-[#120d0a]"
    >
      {/* Oversized so the blur never reveals a hard edge at the viewport border. */}
      <div className="admin-dashboard-scene absolute -inset-6" />
      <div className="absolute inset-0 bg-black/50" />
    </div>
  );
}
