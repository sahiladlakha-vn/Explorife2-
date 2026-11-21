import { Manrope } from "next/font/google";

/**
 * The dashboard's own typeface (spec: Inter or Manrope), loaded only for the
 * routes that render the dashboard rather than app-wide. `vietnamese` is
 * included on purpose: trip names, destinations and the "Tỷ"/"đ" money units
 * all contain Vietnamese letters the `latin` subset doesn't cover. Variable
 * font, so no weight list is needed (the KPIs use the light weights).
 */
export const dashboardFont = Manrope({
  variable: "--font-dashboard",
  subsets: ["latin", "vietnamese"],
  display: "swap",
});
