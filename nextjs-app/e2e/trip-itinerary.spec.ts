import { test, expect } from "@playwright/test";
import { tripTabUrl } from "./fixtures";

/**
 * Covers the fixture data in `lib/dev-preview/fixtures.ts`'s
 * `SAPA_ITINERARY_STOPS`: day 1 has four stops across all three slots, days
 * 4-8 have none (the "Nothing planned yet" empty state).
 */
test.describe("Itinerary day strip and stop list", () => {
  test.use({ viewport: { width: 1024, height: 900 } });

  test("day 1 is selected by default and lists its stops", async ({ page }) => {
    await page.goto(tripTabUrl("itinerary"));

    await expect(page.getByTestId("itinerary-day-strip")).toBeVisible();
    await expect(page.getByTestId("day-chip-1")).toHaveAttribute("aria-selected", "true");

    await expect(page.getByText("Sapa Market")).toBeVisible();
    await expect(page.getByText("Cat Cat Village")).toBeVisible();
    await expect(page.getByText("Fansipan Cable Car")).toBeVisible();
    await expect(page.getByText("Dinner at hotel")).toBeVisible();
  });

  test("selecting an empty day swaps in the empty-slot state", async ({ page }) => {
    await page.goto(tripTabUrl("itinerary"));

    await page.getByTestId("day-chip-4").click();

    await expect(page.getByTestId("day-chip-4")).toHaveAttribute("aria-selected", "true");
    await expect(page.getByTestId("day-chip-1")).toHaveAttribute("aria-selected", "false");
    await expect(page.getByText("Sapa Market")).toHaveCount(0);
    await expect(page.getByText("Nothing planned yet")).toHaveCount(3);
  });

  test("stop rows show cost-TBD and booked status chips", async ({ page }) => {
    await page.goto(tripTabUrl("itinerary"));

    const cableCarRow = page.getByTestId("itinerary-stop-row").filter({ hasText: "Fansipan Cable Car" });
    await expect(cableCarRow.getByText("COST TBD")).toBeVisible();

    const dinnerRow = page.getByTestId("itinerary-stop-row").filter({ hasText: "Dinner at hotel" });
    await expect(dinnerRow.getByText("BOOKED")).toBeVisible();
  });
});

test.describe("Itinerary day panel vs map layout", () => {
  test("desktop: map sits beside the day panel, top-aligned", async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto(tripTabUrl("itinerary"));

    const dayPanel = page.getByTestId("itinerary-day-panel");
    const map = page.getByTestId("itinerary-map");
    await expect(dayPanel).toBeVisible();
    await expect(map).toBeVisible();

    const dayBox = await dayPanel.boundingBox();
    const mapBox = await map.boundingBox();
    if (!dayBox || !mapBox) throw new Error("Missing bounding box for day panel or map");

    expect(mapBox.x).toBeGreaterThan(dayBox.x + dayBox.width / 2);
    expect(Math.abs(mapBox.y - dayBox.y)).toBeLessThan(10);
  });

  test("mobile: map sits below the day panel", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto(tripTabUrl("itinerary"));

    const dayPanel = page.getByTestId("itinerary-day-panel");
    const map = page.getByTestId("itinerary-map");
    await expect(dayPanel).toBeVisible();
    await expect(map).toBeVisible();

    const dayBox = await dayPanel.boundingBox();
    const mapBox = await map.boundingBox();
    if (!dayBox || !mapBox) throw new Error("Missing bounding box for day panel or map");

    expect(mapBox.y).toBeGreaterThanOrEqual(dayBox.y + dayBox.height - 2);
  });
});
