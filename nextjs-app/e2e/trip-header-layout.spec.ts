import { test, expect } from "@playwright/test";
import { BREAKPOINTS, TRIP_TABS, tripTabUrl } from "./fixtures";

/**
 * Encodes the original bug this feature was meant to fix: switching between
 * trip/itinerary/dashboard/bookings must never move or resize the
 * `TripHeader` (switcher + date line + sub-tabs), at any breakpoint.
 */
for (const breakpoint of BREAKPOINTS) {
  test.describe(`TripHeader layout stability at ${breakpoint.width}px`, () => {
    test.use({ viewport: { width: breakpoint.width, height: breakpoint.height } });

    test("bounding box is identical across all four tabs", async ({ page }) => {
      const boxes: Record<string, { x: number; y: number; width: number; height: number }> = {};

      for (const tab of TRIP_TABS) {
        await page.goto(tripTabUrl(tab));
        const header = page.getByTestId("trip-header");
        await expect(header).toBeVisible();
        const box = await header.boundingBox();
        if (!box) throw new Error(`No bounding box for TripHeader on "${tab}" tab`);
        boxes[tab] = box;
      }

      const [firstTab, ...restTabs] = TRIP_TABS;
      const reference = boxes[firstTab];
      for (const tab of restTabs) {
        expect(boxes[tab], `TripHeader box on "${tab}" vs "${firstTab}"`).toEqual(reference);
      }
    });

    test("date line under the trip name is visible on every tab", async ({ page }) => {
      for (const tab of TRIP_TABS) {
        await page.goto(tripTabUrl(tab));
        await expect(page.getByTestId("trip-date-range")).toBeVisible();
      }
    });
  });
}
