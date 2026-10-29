import { test, expect } from "@playwright/test";
import { tripTabUrl } from "./fixtures";

test.describe("TripSwitcher responsive variant", () => {
  test("opens as a popover at >=768px", async ({ page }) => {
    await page.setViewportSize({ width: 1024, height: 900 });
    await page.goto(tripTabUrl("trip"));

    const trigger = page.getByTestId("trip-switcher-trigger");
    await trigger.click();

    await expect(page.getByTestId("trip-switcher-popover")).toBeVisible();
    await expect(page.getByTestId("trip-switcher-sheet")).toHaveCount(0);
  });

  test("opens as a bottom sheet at <768px", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto(tripTabUrl("trip"));

    const trigger = page.getByTestId("trip-switcher-trigger");
    await trigger.click();

    await expect(page.getByTestId("trip-switcher-sheet")).toBeVisible();
    await expect(page.getByTestId("trip-switcher-popover")).toHaveCount(0);
  });

  for (const viewport of [
    { label: "desktop popover", width: 1024, height: 900, testId: "trip-switcher-popover" },
    { label: "mobile sheet", width: 375, height: 812, testId: "trip-switcher-sheet" },
  ] as const) {
    test(`Escape closes the ${viewport.label} and returns focus to the trigger`, async ({ page }) => {
      await page.setViewportSize({ width: viewport.width, height: viewport.height });
      await page.goto(tripTabUrl("trip"));

      const trigger = page.getByTestId("trip-switcher-trigger");
      await trigger.click();
      await expect(page.getByTestId(viewport.testId)).toBeVisible();

      await page.keyboard.press("Escape");

      await expect(page.getByTestId(viewport.testId)).toHaveCount(0);
      await expect(trigger).toBeFocused();
    });
  }
});
