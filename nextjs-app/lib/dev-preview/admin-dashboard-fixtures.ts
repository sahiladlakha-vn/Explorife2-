import "server-only";
import type { AdminDashboardData } from "@/components/features/dashboard/AdminDashboard";

/**
 * Fake `/admin/dashboard` data — no DB, no auth. Typed directly against
 * `AdminDashboardData` so it's structurally guaranteed to match what the real
 * page passes to the same `AdminDashboard` component. Mirrors
 * `DEV_PREVIEW_TRIPS` in `./fixtures.ts`'s relative-date trick so "upcoming"
 * labels never go stale.
 */
const now = new Date();
const daysFromNow = (days: number) => new Date(now.getTime() + days * 86_400_000);
const isoDate = (date: Date) => date.toISOString().slice(0, 10);

export const DEV_PREVIEW_ADMIN_DASHBOARD: AdminDashboardData = {
  admin: { role: "super_admin", email: "admin@explorife.dev" },
  totalUsers: 1842,
  tripsInProgress: { activeCount: 37, totalCount: 212, percentage: 17 },
  upcomingBookingCoverage: { upcomingCount: 64, withBookingCount: 48, percentage: 75 },
  moderation: { totalListings: 326, verifiedCount: 281, pendingCount: 45, percentage: 86, avgTurnaroundHours: 4.3 },
  bookingValue: {
    paidVnd: 1_245_000_000,
    paidCount: 318,
    daily: [-6, -5, -4, -3, -2, -1, 0].map((offset) => ({
      day: isoDate(daysFromNow(offset)),
      count: [2, 4, 1, 5, 3, 6, 4][offset + 6]!,
      amountVnd: [40_000_000, 65_000_000, 18_000_000, 92_000_000, 51_000_000, 110_000_000, 74_000_000][offset + 6]!,
    })),
  },
  bookingFunnel: { toBook: 540, booked: 210, paid: 120 },
  upcomingTrips: [
    {
      id: "fixture-trip-1",
      name: "Sapa Trekking Adventure",
      location: "Sapa",
      startDate: daysFromNow(3).toISOString(),
      endDate: daysFromNow(8).toISOString(),
    },
    {
      id: "fixture-trip-2",
      name: "Da Nang & Hoi An Beach Week",
      location: "Da Nang",
      startDate: daysFromNow(10).toISOString(),
      endDate: daysFromNow(17).toISOString(),
    },
    {
      id: "fixture-trip-3",
      name: "Hanoi Weekend",
      location: "Hanoi",
      startDate: daysFromNow(14).toISOString(),
      endDate: daysFromNow(16).toISOString(),
    },
    {
      id: "fixture-trip-4",
      name: "Phu Quoc Island Getaway",
      location: "Phu Quoc",
      startDate: daysFromNow(21).toISOString(),
      endDate: daysFromNow(27).toISOString(),
    },
    {
      id: "fixture-trip-5",
      name: "Ha Long Bay Cruise",
      location: "Ha Long Bay",
      startDate: daysFromNow(30).toISOString(),
      endDate: daysFromNow(32).toISOString(),
    },
    {
      id: "fixture-trip-6",
      name: "Ho Chi Minh City Food Tour",
      location: "Ho Chi Minh City",
      startDate: daysFromNow(35).toISOString(),
      endDate: daysFromNow(37).toISOString(),
    },
  ],
  recentBookings: [
    {
      id: "fixture-booking-1",
      tripName: "Sapa Trekking Adventure",
      bookingType: "flight",
      amountVnd: 2_500_000,
      status: "paid",
      createdAt: daysFromNow(0).toISOString(),
    },
    {
      id: "fixture-booking-2",
      tripName: "Da Nang & Hoi An Beach Week",
      bookingType: "stay",
      amountVnd: 4_800_000,
      status: "paid",
      createdAt: daysFromNow(-1).toISOString(),
    },
    {
      id: "fixture-booking-3",
      tripName: "Hanoi Weekend",
      bookingType: "activity",
      amountVnd: null,
      status: "to_book",
      createdAt: daysFromNow(-1).toISOString(),
    },
    {
      id: "fixture-booking-4",
      tripName: "Phu Quoc Island Getaway",
      bookingType: "transport",
      amountVnd: 650_000,
      status: "booked",
      createdAt: daysFromNow(-2).toISOString(),
    },
    {
      id: "fixture-booking-5",
      tripName: "Ha Long Bay Cruise",
      bookingType: "stay",
      amountVnd: 6_200_000,
      status: "paid",
      createdAt: daysFromNow(-2).toISOString(),
    },
    {
      id: "fixture-booking-6",
      tripName: "Ho Chi Minh City Food Tour",
      bookingType: "activity",
      amountVnd: 300_000,
      status: "booked",
      createdAt: daysFromNow(-3).toISOString(),
    },
    {
      id: "fixture-booking-7",
      tripName: "Sapa Trekking Adventure",
      bookingType: "stay",
      amountVnd: 3_100_000,
      status: "paid",
      createdAt: daysFromNow(-3).toISOString(),
    },
    {
      id: "fixture-booking-8",
      tripName: "Da Nang & Hoi An Beach Week",
      bookingType: "flight",
      amountVnd: null,
      status: "to_book",
      createdAt: daysFromNow(-4).toISOString(),
    },
  ],
  bookingMix: [
    { bookingType: "flight", count: 142, amountVnd: 410_000_000 },
    { bookingType: "stay", count: 203, amountVnd: 580_000_000 },
    { bookingType: "activity", count: 98, amountVnd: 85_000_000 },
    { bookingType: "transport", count: 97, amountVnd: 60_000_000 },
  ],
  destinationRanking: {
    mode: "usage",
    items: [
      { location: "sapa", tripCount: 42, featured: true },
      { location: "da nang", tripCount: 35, featured: true },
      { location: "hoi an", tripCount: 28, featured: false },
      { location: "ha long bay", tripCount: 24, featured: true },
      { location: "phu quoc", tripCount: 19, featured: false },
      { location: "hanoi", tripCount: 16, featured: false },
    ],
  },
};
