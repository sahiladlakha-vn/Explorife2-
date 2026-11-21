import type { ReactElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, describe, expect, it, vi } from "vitest";

// `next/font/google` only works inside Next's compiler pipeline. The real
// `.variable` is a generated class name (`__variable_<hash>`); the stand-in must
// not start with `font-`, or tailwind-merge would fold it into `font-dash`.
vi.mock("./fonts", () => ({ dashboardFont: { variable: "__variable_dashboard_test" } }));

import {
  DEV_PREVIEW_ADMIN_DASHBOARD,
  DEV_PREVIEW_ADMIN_DASHBOARD_EMPTY,
  DEV_PREVIEW_ADMIN_DASHBOARD_ERRORS,
} from "@/lib/dev-preview/admin-dashboard-fixtures";
import { failed, ok } from "@/lib/dashboard/section";
import type {
  BookingMixEntry,
  BookingValueSummary,
  ByPeriod,
  DestinationRanking,
  ModerationStats,
  RecentBookingItem,
  UpcomingWeek,
} from "@/lib/dashboard/types";
import { AdminDashboard } from "./AdminDashboard";
import { BookingFunnelCard } from "./BookingFunnelCard";
import { BookingMixCard } from "./BookingMixCard";
import { BookingValueCard } from "./BookingValueCard";
import { BookingVelocityCard } from "./BookingVelocityCard";
import { DashboardHeader } from "./DashboardHeader";
import { DashboardTopBar } from "./DashboardTopBar";
import { DestinationRankingCard } from "./DestinationRankingCard";
import { ModerationCard } from "./ModerationCard";
import { RecentBookingsCard } from "./RecentBookingsCard";
import { TripsInProgressCard } from "./TripsInProgressCard";
import { UpcomingTripsCard } from "./UpcomingTripsCard";
import { ChangeBadge } from "./primitives/ChangeBadge";

// These are markup tests: Node environment, `renderToStaticMarkup`, assertions
// on the HTML. Anything that needs a browser — the Month/Quarter/Year toggle,
// count-up, hover — is covered by e2e/admin-dashboard.spec.ts.

const render = (element: ReactElement): string => renderToStaticMarkup(element);

const ENTITIES: Record<string, string> = {
  "&amp;": "&",
  "&lt;": "<",
  "&gt;": ">",
  "&quot;": '"',
  "&#x27;": "'",
};

/** What a person reads: tags removed, entities decoded, whitespace collapsed. */
function text(html: string): string {
  return html
    .replace(/<[^>]*>/g, " ")
    .replace(/&(?:amp|lt|gt|quot|#x27);/g, (entity) => ENTITIES[entity]!)
    .replace(/\s+/g, " ")
    .trim();
}

const count = (html: string, needle: string): number => html.split(needle).length - 1;

/** The `aria-valuenow` of the progress bar with this accessible name. */
function progressValue(html: string, label: string): number {
  const tag = new RegExp(`<div[^>]*aria-label="${label}"[^>]*>`).exec(html)?.[0];
  if (!tag) throw new Error(`no progress bar named "${label}"`);
  return Number(/aria-valuenow="(\d+)"/.exec(tag)![1]);
}

/** Tooltips (`title="…"`) of the chart columns inside one block of markup, in order. */
const titles = (html: string): string[] =>
  [...html.matchAll(/title="([^"]*)"/g)].map((m) => text(m[1]!));

const populated = DEV_PREVIEW_ADMIN_DASHBOARD;

/** The `AdminDashboard` data prop, with a few sections swapped out. */
const populatedWith = (overrides: Partial<typeof populated>) => ({ ...populated, ...overrides });

afterEach(() => {
  vi.useRealTimers();
});

describe("AdminDashboard — populated", () => {
  const html = render(<AdminDashboard data={populated} />);

  it("renders the greeting, the three header pills and every card", () => {
    for (const id of [
      "card-welcome",
      "kpi-total-users",
      "kpi-active-trips",
      "kpi-booking-value",
      "card-booking-value",
      "card-trips-in-progress",
      "card-booking-velocity",
      "card-booking-funnel",
      "card-recent-bookings",
      "card-upcoming-trips",
      "card-destinations",
      "card-booking-mix",
      "card-moderation",
    ]) {
      expect(html, id).toContain(`data-testid="${id}"`);
    }
    expect(html).toContain('data-testid="week-strip"');
    expect(html).toContain("Performance Overview");
  });

  it("has no empty or error states when every query returned data", () => {
    expect(html).not.toContain('data-state="error"');
    expect(html).not.toContain('data-state="empty"');
  });

  it('says "Booking Value", never "Revenue" — bookings are what travelers logged as paid', () => {
    expect(text(html)).not.toMatch(/revenue/i);
    expect(text(html)).toContain("Booking Value (Paid)");
  });

  it("has no search box or notification bell", () => {
    // Guard against a vacuous pass: lucide icons do carry their name as a class.
    expect(html).toContain("lucide-compass");
    expect(html).not.toContain("lucide-search");
    expect(html).not.toContain("lucide-bell");
    expect(html).not.toContain('type="search"');
    expect(html).not.toContain('role="search"');
  });

  it("is dashboard-scoped: own font class on the root, glass cards, dark card for Recent Bookings", () => {
    expect(html).toContain("__variable_dashboard_test");
    expect(html).toContain("admin-dashboard font-dash");
    expect(count(html, "glass-card-dark")).toBe(1);
    expect(html).toContain("glass-card ");
  });

  it("gives every card but the welcome card exactly one corner arrow, and it is visibly inert", () => {
    // One segment per card / KPI: from its test id up to the next one's.
    const segments = html.split(/(?=data-testid="(?:card|kpi)-)/).slice(1);
    const withArrows = segments.filter((segment) => !segment.startsWith('data-testid="card-welcome"'));
    expect(withArrows).toHaveLength(12); // 3 KPIs + 9 cards
    for (const segment of withArrows) {
      expect(count(segment, "Details (coming soon)"), segment.slice(0, 40)).toBe(1);
    }

    const arrows = [...html.matchAll(/<button[^>]*>(?:(?!<\/button>)[\s\S])*?Details \(coming soon\)/g)];
    expect(arrows).toHaveLength(12);
    for (const [arrow] of arrows) {
      expect(arrow).toContain('title="Coming soon"');
      expect(arrow).toContain('aria-disabled="true"');
      expect(arrow).toContain("cursor-not-allowed");
      expect(arrow).toContain("opacity-50");
    }
  });

  it("renders identically whatever the clock says — a static route must never read `new Date()`", () => {
    // recharts numbers its clip-path ids from a module counter; that is not the clock.
    const stable = (markup: string) => markup.replace(/recharts\d+/g, "recharts#");

    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-01-01T00:00:00Z"));
    const earlier = stable(render(<AdminDashboard data={populated} />));
    vi.setSystemTime(new Date("2031-06-30T20:00:00Z"));
    const later = stable(render(<AdminDashboard data={populated} />));

    expect(later).toBe(earlier);
  });
});

describe("AdminDashboard — empty environment", () => {
  const html = render(<AdminDashboard data={DEV_PREVIEW_ADMIN_DASHBOARD_EMPTY} />);

  it("shows a designed empty state in every card and no error state", () => {
    expect(html).not.toContain('data-state="error"');
    // Booking Value, Trips in Progress, Velocity, Funnel, Recent Bookings,
    // Upcoming Trips, Destinations, Booking Mix and Moderation.
    expect(count(html, 'data-state="empty"')).toBe(9);
  });

  it("keeps the header intact with zeroed pills and no 'Welcome back, null'", () => {
    expect(progressValue(html, "Upcoming trips booked")).toBe(0);
    expect(progressValue(html, "Trips completed")).toBe(0);
    expect(progressValue(html, "Listings verified")).toBe(0);
    expect(text(html)).toContain("Welcome back");
    expect(text(html)).not.toMatch(/null|undefined|NaN/);
  });
});

describe("AdminDashboard — partial failure", () => {
  const html = render(<AdminDashboard data={DEV_PREVIEW_ADMIN_DASHBOARD_ERRORS} />);

  it("puts an error state on each failed card only", () => {
    // Booking Value, Funnel, Upcoming Trips, Recent Bookings, Destinations, Booking Mix.
    expect(count(html, 'data-state="error"')).toBe(6);
    expect(count(html, 'role="alert"')).toBe(6);
  });

  it("leaves the cards whose queries succeeded rendering real data", () => {
    const section = (id: string) => html.slice(html.indexOf(`data-testid="${id}"`)).split('data-testid="card-')[1] ?? "";
    expect(section("card-trips-in-progress")).toContain("37 of 212 trips active today");
    expect(section("card-booking-velocity")).toContain("bookings in the last 14 days");
    expect(section("card-moderation")).toContain("verified");
  });

  it("marks failed header numbers as unavailable instead of showing 0", () => {
    expect(html).toContain('aria-label="Unavailable"');
    const users = html.slice(html.indexOf('data-testid="kpi-total-users"'));
    expect(users.slice(0, users.indexOf('data-testid="kpi-active-trips"'))).toContain("—");
  });
});

describe("DashboardHeader", () => {
  const props = {
    totalUsers: populated.totalUsers,
    trips: populated.trips,
    coverage: populated.upcomingBookingCoverage,
    moderation: populated.moderation,
    bookingValue: populated.bookingValue,
  };

  it("greets the admin by name", () => {
    const html = render(<DashboardHeader name="Linh" {...props} />);
    expect(text(/<h1[\s\S]*<\/h1>/.exec(html)![0])).toBe("Welcome back, Linh");
  });

  it("greets without a name when the profile has none", () => {
    const html = render(<DashboardHeader name={null} {...props} />);
    expect(text(/<h1[\s\S]*<\/h1>/.exec(html)![0])).toBe("Welcome back");
  });

  it("renders the greeting from a fixed server snapshot, not the clock", () => {
    const html = render(<DashboardHeader name="Linh" {...props} />);
    expect(html).toMatch(/data-testid="greeting"[^>]*>Welcome</);
  });

  it("shows the three header pills with their real percentages", () => {
    const html = render(<DashboardHeader name="Linh" {...props} />);
    expect(progressValue(html, "Upcoming trips booked")).toBe(75);
    expect(progressValue(html, "Trips completed")).toBe(60);
    expect(progressValue(html, "Listings verified")).toBe(86);
  });

  it("labels the KPIs Total Users, Active Trips and Booking Value — not Total Trips", () => {
    const html = render(<DashboardHeader name="Linh" {...props} />);
    const read = text(html);
    expect(read).toContain("Total Users");
    expect(read).toContain("Active Trips");
    expect(read).toContain("of 212 trips");
    expect(read).toContain("Booking Value");
    expect(read).not.toContain("Total Trips");
  });

  it("shows an em dash for a pill whose query failed", () => {
    const html = render(<DashboardHeader name="Linh" {...props} coverage={failed()} />);
    expect(progressValue(html, "Upcoming trips booked")).toBe(0);
    expect(text(/aria-label="Upcoming trips booked"[\s\S]*?<\/span>\s*<\/div>/.exec(html)![0])).toContain("—");
  });
});

describe("DashboardTopBar", () => {
  const html = render(<DashboardTopBar admin={{ role: "super_admin", name: "Linh" }} />);

  it("links only the real Dashboard route, marked as the current page", () => {
    const links = [...html.matchAll(/<a [^>]*>/g)].map((m) => m[0]);
    expect(links).toHaveLength(1);
    expect(links[0]).toContain('href="/admin/dashboard"');
    expect(links[0]).toContain('aria-current="page"');
    expect(links[0]).toContain("bg-white text-neutral-900");
  });

  it("renders every unbuilt section as a disabled pill with a Coming soon tooltip", () => {
    const buttons = [...html.matchAll(/<button[^>]*>([^<]*)<\/button>/g)];
    expect(buttons.map((m) => m[1])).toEqual([
      "Users",
      "Trips",
      "Bookings",
      "Moderation",
      "Destinations",
      "Settings",
    ]);
    for (const [button] of buttons) {
      expect(button).toContain('title="Coming soon"');
      expect(button).toContain('aria-disabled="true"');
      expect(button).toContain("opacity-50");
      expect(button).toContain("cursor-not-allowed");
    }
  });

  it("shows the admin's role and initial, falling back to the role when there is no name", () => {
    expect(text(html)).toContain("Super Admin");
    expect(html).toContain(">L<");
    const nameless = render(<DashboardTopBar admin={{ role: "super_admin", name: null }} />);
    expect(nameless).toContain(">S<");
  });
});

describe("BookingValueCard", () => {
  const summary = (overrides: Partial<BookingValueSummary>): BookingValueSummary => ({
    ...(populated.bookingValue.status === "ok" ? populated.bookingValue.data : (undefined as never)),
    ...overrides,
  });

  it("charts the last 7 days by weekday, today last, with the week total", () => {
    const html = render(<BookingValueCard section={populated.bookingValue} />);
    expect(text(html)).toContain("450 tr đ");
    expect(text(html)).toContain("paid in the last 7 days");
    expect(titles(html).filter((t) => t.includes("·"))).toEqual([
      "Fri Nov 13 · 60 tr đ",
      "Sat Nov 14 · 45 tr đ",
      "Sun Nov 15 · 92 tr đ",
      "Mon Nov 16 · 55 tr đ",
      "Tue Nov 17 · 110 tr đ",
      "Wed Nov 18 · 38 tr đ",
      "Thu Nov 19 · 50 tr đ",
    ]);
  });

  it("shows an emerald +N% badge when the week is up on the one before", () => {
    const html = render(<BookingValueCard section={populated.bookingValue} />);
    expect(html).toMatch(/data-tone="up"/);
    expect(text(html)).toContain("+18%");
  });

  it("shows a rose -N% badge when the week is down", () => {
    const html = render(
      <BookingValueCard section={ok(summary({ last7Vnd: 50_000_000, prev7Vnd: 100_000_000, changePercent: -50 }))} />,
    );
    expect(html).toMatch(/data-tone="down"/);
    expect(text(html)).toContain("-50%");
  });

  it('shows "New" instead of a percentage when the previous week had no paid bookings', () => {
    const html = render(
      <BookingValueCard section={ok(summary({ last7Vnd: 5_000_000, prev7Vnd: 0, changePercent: null }))} />,
    );
    const badge = /<span data-tone="[^"]*"[\s\S]*?<span class="sr-only">[^<]*<\/span><\/span>/.exec(html)![0];
    expect(badge).toContain('data-tone="neutral"');
    expect(text(badge)).toContain("New");
    expect(text(badge)).not.toContain("%");
    expect(text(html)).not.toMatch(/Infinity|NaN/);
  });

  it("shows an empty state, and no badge, when nothing was paid in the last 7 days", () => {
    const empty = DEV_PREVIEW_ADMIN_DASHBOARD_EMPTY.bookingValue;
    const html = render(<BookingValueCard section={empty} />);
    expect(html).toContain('data-state="empty"');
    expect(text(html)).toContain("No paid bookings in the last 7 days");
    expect(html).not.toContain("data-tone");
  });

  it("shows an error state when the query failed", () => {
    const html = render(<BookingValueCard section={failed()} />);
    expect(html).toContain('role="alert"');
    expect(text(html)).toContain("Couldn't load booking value");
  });
});

describe("ChangeBadge", () => {
  it("is neutral at exactly 0%", () => {
    const html = render(<ChangeBadge percent={0} hasCurrent />);
    expect(html).toContain('data-tone="neutral"');
    expect(text(html)).toContain("0%");
  });

  it("renders nothing with no baseline and no current value", () => {
    expect(render(<ChangeBadge percent={null} hasCurrent={false} />)).toBe("");
  });

  it("spells the change out for screen readers", () => {
    expect(text(render(<ChangeBadge percent={-12} hasCurrent />))).toContain(
      "12 percent down versus the previous 7 days",
    );
  });
});

describe("BookingVelocityCard", () => {
  it("shows the 14-day total, the daily average and the date range", () => {
    const html = render(<BookingVelocityCard section={populated.bookingVelocity} />);
    expect(text(html)).toContain("82");
    expect(text(html)).toContain("bookings in the last 14 days · 5.9 a day");
    expect(text(html)).toContain("Nov 6 – Nov 19");
  });

  it("uses an empty state for a quiet fortnight", () => {
    const html = render(<BookingVelocityCard section={DEV_PREVIEW_ADMIN_DASHBOARD_EMPTY.bookingVelocity} />);
    expect(html).toContain('data-state="empty"');
  });
});

describe("BookingFunnelCard", () => {
  it("shows the cumulative stages and conversion between them", () => {
    const html = render(<BookingFunnelCard section={populated.bookingFunnel} />);
    expect(progressValue(html, "To Book")).toBe(100);
    expect(progressValue(html, "Booked")).toBe(39);
    expect(progressValue(html, "Paid")).toBe(22);
    expect(text(html)).toContain("39% booked · 57% of booked paid");
  });
});

describe("TripsInProgressCard", () => {
  it("shows the dial and the active/total counts", () => {
    const html = render(<TripsInProgressCard section={populated.trips} />);
    expect(html).toContain('aria-label="17 percent"');
    expect(text(html)).toContain("37 of 212 trips active today");
  });
});

describe("RecentBookingsCard", () => {
  const booking = (overrides: Partial<RecentBookingItem>): RecentBookingItem => ({
    id: "b",
    tripName: "Hanoi Weekend",
    bookingType: "stay",
    amountVnd: 1_000_000,
    status: "booked",
    createdAt: "2026-11-19T08:00:00Z",
    ...overrides,
  });

  it('counts paid bookings among those shown as "x/y paid"', () => {
    const html = render(<RecentBookingsCard section={populated.recentBookings} />);
    expect(html).toMatch(/data-testid="paid-counter"[^>]*>4\/8 paid</);
  });

  it("lists trip, type, compact VND amount, status and date", () => {
    const html = render(<RecentBookingsCard section={populated.recentBookings} />);
    const read = text(html);
    expect(read).toContain("Sapa Trekking Adventure");
    expect(read).toContain("Da Nang & Hoi An Beach Week");
    expect(read).toContain("2,5 tr đ");
    expect(read).toContain("650.000 đ");
    expect(read).toContain("Paid");
    expect(read).toContain("To Book");
    expect(read).toContain("Booked");
  });

  it("shows an em dash, not 0 đ, for a booking with no amount", () => {
    const html = render(
      <RecentBookingsCard section={ok([booking({ amountVnd: null, status: "to_book" })])} />,
    );
    expect(text(html)).toContain("—");
    expect(text(html)).not.toContain("0 đ");
  });

  it("dates a booking by its Vietnam calendar day, not its UTC day", () => {
    // 19:40 UTC on the 16th is 02:40 on the 17th in Vietnam (UTC+7).
    const html = render(<RecentBookingsCard section={ok([booking({ createdAt: "2026-11-16T19:40:00Z" })])} />);
    expect(text(html)).toContain("Nov 17");
    expect(text(html)).not.toContain("Nov 16");
  });

  it("never prints anything beyond the whitelisted fields — no e-mail, no phone", () => {
    const leaky = {
      ...booking({}),
      email: "traveler@example.com",
      phone: "+84 90 123 4567",
      userId: "user-123",
    } as RecentBookingItem;
    const html = render(<RecentBookingsCard section={ok([leaky])} />);
    expect(html).not.toContain("traveler@example.com");
    expect(html).not.toContain("+84");
    expect(html).not.toContain("user-123");
    expect(html).not.toContain("@");
  });

  it("is the dark glass variant", () => {
    expect(render(<RecentBookingsCard section={populated.recentBookings} />)).toContain("glass-card-dark");
  });

  it("shows an empty state with no counter when there are no bookings", () => {
    const html = render(<RecentBookingsCard section={ok([])} />);
    expect(html).toContain('data-state="empty"');
    expect(text(html)).toContain("No bookings yet");
    expect(html).not.toContain("paid-counter");
  });

  it("shows an error state with no counter when the query failed", () => {
    const html = render(<RecentBookingsCard section={failed()} />);
    expect(html).toContain('data-state="error"');
    expect(html).not.toContain("paid-counter");
  });
});

describe("UpcomingTripsCard", () => {
  const week = (overrides: Partial<UpcomingWeek>): UpcomingWeek => ({
    weekStart: "2026-11-16",
    today: "2026-11-19",
    trips: [],
    nextTrip: null,
    ...overrides,
  });

  it("draws Monday to Sunday with only today highlighted", () => {
    const html = render(<UpcomingTripsCard section={populated.upcomingWeek} />);
    const strip = /data-testid="week-strip"[\s\S]*/.exec(html)![0];
    expect([...strip.matchAll(/text-\[11px\] font-medium uppercase">(\w+)</g)].map((m) => m[1])).toEqual([
      "Mon",
      "Tue",
      "Wed",
      "Thu",
      "Fri",
      "Sat",
      "Sun",
    ]);
    expect(count(html, 'data-today="true"')).toBe(1);
    const today = /<div data-today="true"[\s\S]*?<\/div>/.exec(html)![0];
    expect(text(today)).toBe("Thu 19");
  });

  it("draws a bar per trip, clipped to the week, and names the next trip", () => {
    const html = render(<UpcomingTripsCard section={populated.upcomingWeek} />);
    expect(count(html, 'data-testid="week-trip"')).toBe(4);
    const read = text(html);
    expect(read).toContain("Da Nang & Hoi An Beach Week");
    expect(read).toContain("Sapa Trekking Adventure");
    expect(read).toContain("Next up: Phu Quoc Island Getaway · Nov 30 → Dec 6");
  });

  it("collapses trips beyond four overlapping lanes into a +N more note", () => {
    const trips = Array.from({ length: 6 }, (_, i) => ({
      id: `t${i}`,
      name: `Trip ${i}`,
      location: "Sapa",
      startDate: "2026-11-17",
      endDate: "2026-11-19",
    }));
    const html = render(<UpcomingTripsCard section={ok(week({ trips }))} />);
    expect(count(html, 'data-testid="week-trip"')).toBe(4);
    expect(text(html)).toContain("+2 more this week");
  });

  it("says so when no trip is running this week, still pointing at the next one", () => {
    const next = { id: "n", name: "Phu Quoc", location: "Phu Quoc", startDate: "2026-11-30", endDate: "2026-12-02" };
    const html = render(<UpcomingTripsCard section={ok(week({ nextTrip: next }))} />);
    expect(html).toContain('data-state="empty"');
    expect(text(html)).toContain("No trips this week");
    expect(text(html)).toContain("Next up: Phu Quoc");
    expect(html).not.toContain('data-testid="week-trip"');
  });

  it("shows the empty state alone on a calendar with no trips at all", () => {
    const html = render(<UpcomingTripsCard section={ok(week({}))} />);
    expect(text(html)).toContain("No trips this week");
    expect(text(html)).not.toContain("Next up");
  });

  it("shows an error state when the query failed", () => {
    const html = render(<UpcomingTripsCard section={failed()} />);
    expect(html).toContain('role="alert"');
    expect(html).not.toContain("week-strip");
  });
});

describe("Performance Overview cards", () => {
  const destinations = populated.destinations.status === "ok" ? populated.destinations.data : (undefined as never);
  const mix = populated.bookingMix.status === "ok" ? populated.bookingMix.data : (undefined as never);
  const moderation = populated.moderationByPeriod.status === "ok" ? populated.moderationByPeriod.data : (undefined as never);

  const rankingOf = (period: "month" | "quarter" | "year", ranking?: ByPeriod<DestinationRanking>) =>
    render(<DestinationRankingCard section={ok(ranking ?? destinations)} period={period} />);

  it("ranks destinations for the chosen window, with a Featured badge", () => {
    const quarter = rankingOf("quarter");
    expect(text(quarter)).toContain("Top Destinations");
    expect(text(quarter)).toMatch(/1 sapa Featured 42 trips/);
    expect(count(quarter, "Featured")).toBe(3);

    const year = rankingOf("year");
    expect(text(year)).toMatch(/1 da nang Featured 160 trips/);
  });

  it("switches to editorial Featured Destinations when there is no usage at all", () => {
    const editorial: ByPeriod<DestinationRanking> = {
      month: { mode: "editorial", items: [{ title: "Sapa" }] },
      quarter: { mode: "editorial", items: [{ title: "Sapa" }] },
      year: { mode: "editorial", items: [{ title: "Sapa" }] },
    };
    const html = rankingOf("quarter", editorial);
    expect(text(html)).toContain("Featured Destinations");
    expect(text(html)).toContain("1 Sapa");
  });

  it("names the window in the empty state of a quiet period", () => {
    const quiet: ByPeriod<DestinationRanking> = {
      ...destinations,
      month: { mode: "usage", items: [] },
    };
    expect(text(rankingOf("month", quiet))).toContain("No trips created in the last 30 days");
  });

  it("shows the booking mix per type for the chosen window, by count", () => {
    const html = render(<BookingMixCard section={ok(mix)} period="month" />);
    const rows = [...html.matchAll(/data-booking-type="(\w+)"[\s\S]*?tabular-nums">([^<]+)</g)].map((m) => [m[1], m[2]]);
    expect(rows).toEqual([
      ["flight", "41"],
      ["stay", "58"],
      ["activity", "27"],
      ["transport", "19"],
    ]);
  });

  it("explains an empty booking mix window", () => {
    const quiet: ByPeriod<BookingMixEntry[]> = {
      ...mix,
      year: mix.year.map((m) => ({ ...m, count: 0, amountVnd: 0 })),
    };
    const html = render(<BookingMixCard section={ok(quiet)} period="year" />);
    expect(text(html)).toContain("No bookings in the last 365 days");
  });

  it("shows verification progress, counts and turnaround for the chosen window", () => {
    const month = render(<ModerationCard section={ok(moderation)} period="month" />);
    expect(progressValue(month, "Verified")).toBe(71);
    expect(text(month)).toContain("22 verified · 9 pending");
    expect(text(month)).toContain("3.1 h average turnaround");

    const year = render(<ModerationCard section={ok(moderation)} period="year" />);
    expect(text(year)).toContain("281 verified · 45 pending");
    expect(text(year)).toContain("4.3 h average turnaround");
  });

  it("explains a window with no listings, and one with nothing verified yet", () => {
    const none: ModerationStats = {
      totalListings: 0,
      verifiedCount: 0,
      pendingCount: 0,
      percentage: 0,
      avgTurnaroundHours: null,
    };
    const empty = render(
      <ModerationCard section={ok({ month: none, quarter: none, year: none })} period="quarter" />,
    );
    expect(text(empty)).toContain("No listings created in the last 90 days");

    const unverified: ModerationStats = { ...none, totalListings: 3, pendingCount: 3 };
    const html = render(
      <ModerationCard section={ok({ month: unverified, quarter: unverified, year: unverified })} period="quarter" />,
    );
    expect(text(html)).toContain("No verifications yet");
  });

  it("shows an error state per card when its query failed", () => {
    expect(render(<DestinationRankingCard section={failed()} period="quarter" />)).toContain('role="alert"');
    expect(render(<BookingMixCard section={failed()} period="quarter" />)).toContain('role="alert"');
    expect(render(<ModerationCard section={failed()} period="quarter" />)).toContain('role="alert"');
  });

  it("defaults the toggle to Quarter", () => {
    const html = render(<AdminDashboard data={populatedWith({})} />);
    const group = /role="group" aria-label="Performance period"[\s\S]*?<\/div>/.exec(html)![0];
    expect(group).toMatch(/aria-pressed="true"[^>]*data-value="quarter"/);
    expect(count(group, 'aria-pressed="true"')).toBe(1);
    // …and the cards below show the quarter window (90 days), not month (12) or year (151).
    expect(text(html)).toContain("1 sapa Featured 42 trips");
    expect(text(html)).toContain("88 verified · 21 pending");
  });
});
