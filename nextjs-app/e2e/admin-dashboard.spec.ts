import { test, expect, type Page } from "@playwright/test";
import { BREAKPOINTS } from "./fixtures";

/**
 * `/dev-preview/admin/dashboard` renders the real `AdminDashboard` component
 * from static fixtures (no database, no auth) — populated, `/empty` and
 * `/errors`. Fixture numbers below mirror `lib/dev-preview/admin-dashboard-fixtures.ts`
 * by hand, since e2e/ may not import server-only code.
 */
const POPULATED = "/dev-preview/admin/dashboard";
const EMPTY = "/dev-preview/admin/dashboard/empty";
const ERRORS = "/dev-preview/admin/dashboard/errors";

const CARDS = [
  "card-booking-value",
  "card-trips-in-progress",
  "card-booking-velocity",
  "card-booking-funnel",
  "card-recent-bookings",
  "card-upcoming-trips",
  "card-destinations",
  "card-booking-mix",
  "card-moderation",
] as const;

/** Collects everything that would show up as a red line in the browser console. */
function trackConsoleErrors(page: Page): string[] {
  const errors: string[] = [];
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });
  page.on("pageerror", (error) => errors.push(error.message));
  return errors;
}

/** Horizontal overflow of the page itself, in px (<= 0 means none). */
async function pageOverflow(page: Page): Promise<number> {
  return page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
}

/** Ids of cards or KPIs whose content spills out of their own box. */
async function overflowingCards(page: Page): Promise<string[]> {
  return page.evaluate(() =>
    [...document.querySelectorAll<HTMLElement>('[data-testid^="card-"], [data-testid^="kpi-"]')]
      .filter((card) => card.scrollWidth > card.clientWidth + 1)
      .map((card) => card.dataset.testid!),
  );
}

/**
 * Records every text the Total Users KPI ever shows. Install before `goto`.
 * With the count-up that is a long run of intermediate numbers; without it
 * (reduced motion) just the server-rendered 0 and the final value.
 */
async function recordKpiValues(page: Page): Promise<void> {
  await page.addInitScript(() => {
    const seen = new Set<string>();
    (window as unknown as { __kpiValues: Set<string> }).__kpiValues = seen;
    new MutationObserver(() => {
      const value = document.querySelector('[data-testid="kpi-total-users"] .tabular-nums');
      if (value?.textContent) seen.add(value.textContent);
    }).observe(document, { childList: true, characterData: true, subtree: true });
  });
}

async function seenKpiValues(page: Page): Promise<string[]> {
  return page.evaluate(() => [...(window as unknown as { __kpiValues: Set<string> }).__kpiValues]);
}

test.describe("populated dashboard", () => {
  test("renders the header, every card and the real numbers, with no console errors", async ({ page }) => {
    const errors = trackConsoleErrors(page);
    await page.goto(POPULATED);

    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Welcome back, Linh");
    for (const id of CARDS) await expect(page.getByTestId(id), id).toBeVisible();

    // KPIs count up from 0, so wait for the final value.
    await expect(page.getByTestId("kpi-total-users")).toContainText("1,842");
    await expect(page.getByTestId("kpi-active-trips")).toContainText("37");
    await expect(page.getByTestId("kpi-active-trips")).toContainText("of 212 trips");
    await expect(page.getByTestId("kpi-booking-value")).toContainText("1,2 Tỷ đ");

    await expect(page.getByTestId("paid-counter")).toHaveText("4/8 paid");
    await expect(page.getByTestId("card-booking-value")).toContainText("+18%");

    expect(errors, "console errors").toEqual([]);
  });

  test("the week strip starts on Monday and highlights today", async ({ page }) => {
    await page.goto(POPULATED);
    const strip = page.getByTestId("week-strip");
    expect(await strip.locator("p.uppercase").allTextContents()).toEqual([
      "Mon",
      "Tue",
      "Wed",
      "Thu",
      "Fri",
      "Sat",
      "Sun",
    ]);
    await expect(strip.locator('[data-today="true"]')).toHaveCount(1);
    await expect(strip.locator('[data-today="true"]')).toContainText("Thu");
    await expect(strip.locator('[data-today="true"]')).toContainText("19");
    await expect(page.getByTestId("week-trip")).toHaveCount(4);
  });

  test("the greeting is filled in after hydration, never baked into the static HTML", async ({ page, request }) => {
    const html = await (await request.get(POPULATED)).text();
    expect(html).toMatch(/data-testid="greeting"[^>]*>Welcome</);

    await page.goto(POPULATED);
    await expect(page.getByTestId("greeting")).toHaveText(/^Good (morning|afternoon|evening)$/);
  });

  test("the Month / Quarter / Year toggle re-ranks all three Performance Overview cards", async ({ page }) => {
    await page.goto(POPULATED);
    const toggle = page.getByRole("group", { name: "Performance period" });
    const destinations = page.getByTestId("card-destinations");
    const moderation = page.getByTestId("card-moderation");

    // Quarter (90 days) is the default.
    await expect(toggle.getByRole("button", { name: "Quarter" })).toHaveAttribute("aria-pressed", "true");
    await expect(destinations.getByRole("listitem").first()).toContainText("sapa");
    await expect(destinations.getByRole("listitem").first()).toContainText("42 trips");
    await expect(moderation).toContainText("88 verified · 21 pending");

    await toggle.getByRole("button", { name: "Month" }).click();
    await expect(toggle.getByRole("button", { name: "Month" })).toHaveAttribute("aria-pressed", "true");
    await expect(toggle.getByRole("button", { name: "Quarter" })).toHaveAttribute("aria-pressed", "false");
    await expect(destinations.getByRole("listitem").first()).toContainText("12 trips");
    await expect(moderation).toContainText("22 verified · 9 pending");
    await expect(page.getByTestId("card-booking-mix").locator('[data-booking-type="flight"]')).toContainText("41");

    await toggle.getByRole("button", { name: "Year" }).click();
    await expect(destinations.getByRole("listitem").first()).toContainText("da nang");
    await expect(destinations.getByRole("listitem").first()).toContainText("160 trips");
    await expect(moderation).toContainText("281 verified · 45 pending");
    await expect(page.getByTestId("card-booking-mix").locator('[data-booking-type="flight"]')).toContainText("612");
  });

  test("Booking Mix switches between counts and booked value", async ({ page }) => {
    await page.goto(POPULATED);
    const mix = page.getByTestId("card-booking-mix");
    const flight = mix.locator('[data-booking-type="flight"]');

    await expect(flight).toContainText("142"); // quarter, by count
    await mix.getByRole("button", { name: "Value" }).click();
    await expect(flight).toContainText("410 tr đ");
    await mix.getByRole("button", { name: "Bookings" }).click();
    await expect(flight).toContainText("142");
  });
});

test.describe("placeholder navigation", () => {
  test("only Dashboard is a link; the unbuilt sections and corner arrows are inert", async ({ page }) => {
    await page.goto(POPULATED);
    const url = page.url();

    const nav = page.getByRole("navigation", { name: "Admin sections" });
    await expect(nav.getByRole("link")).toHaveCount(1);
    await expect(nav.getByRole("link", { name: "Dashboard" })).toHaveAttribute("aria-current", "page");

    for (const name of ["Users", "Trips", "Bookings", "Moderation", "Destinations", "Settings"]) {
      const pill = nav.getByRole("button", { name });
      await expect(pill, name).toHaveAttribute("title", "Coming soon");
      await expect(pill, name).toHaveAttribute("aria-disabled", "true");
      await expect(pill, name).toHaveCSS("opacity", "0.5");
      await expect(pill, name).toHaveCSS("cursor", "not-allowed");
      // `force`: Playwright treats aria-disabled as "not enabled" and would wait forever.
      await pill.click({ force: true });
    }

    const arrows = page.getByRole("button", { name: "Details (coming soon)" });
    await expect(arrows).toHaveCount(12);
    for (const arrow of await arrows.all()) {
      await expect(arrow).toHaveAttribute("title", "Coming soon");
      await expect(arrow).toHaveCSS("cursor", "not-allowed");
      await arrow.click({ force: true });
    }

    expect(page.url(), "clicking placeholders must not navigate").toBe(url);
  });

  test("has no search field or notification bell", async ({ page }) => {
    await page.goto(POPULATED);
    await expect(page.getByRole("searchbox")).toHaveCount(0);
    await expect(page.getByRole("search")).toHaveCount(0);
    await expect(page.locator(".lucide-search, .lucide-bell")).toHaveCount(0);
  });
});

test.describe("empty and error states", () => {
  test("an empty environment shows a designed empty state in all nine cards", async ({ page }) => {
    const errors = trackConsoleErrors(page);
    await page.goto(EMPTY);

    for (const id of CARDS) {
      await expect(page.getByTestId(id).locator('[data-state="empty"]'), id).toHaveCount(1);
    }
    await expect(page.locator('[data-state="error"]')).toHaveCount(0);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Welcome back");
    expect(errors, "console errors").toEqual([]);
  });

  test("a partial failure puts an error state on the failed cards only", async ({ page }) => {
    const errors = trackConsoleErrors(page);
    await page.goto(ERRORS);

    const failedCards = [
      "card-booking-value",
      "card-booking-funnel",
      "card-upcoming-trips",
      "card-recent-bookings",
      "card-destinations",
      "card-booking-mix",
    ];
    for (const id of failedCards) {
      await expect(page.getByTestId(id).getByRole("alert"), id).toHaveCount(1);
    }
    // (Not `getByRole("alert")` page-wide: Next's route announcer is a role=alert too.)
    await expect(page.locator('[data-state="error"]')).toHaveCount(failedCards.length);

    // The cards whose queries succeeded are untouched.
    await expect(page.getByTestId("card-trips-in-progress")).toContainText("37 of 212 trips active today");
    await expect(page.getByTestId("card-booking-velocity")).toContainText("bookings in the last 14 days");
    await expect(page.getByTestId("card-moderation")).toContainText("verified");

    // A failed KPI says so rather than showing 0.
    await expect(page.getByTestId("kpi-total-users").getByLabel("Unavailable")).toBeVisible();
    expect(errors, "console errors").toEqual([]);
  });
});

for (const breakpoint of BREAKPOINTS) {
  test.describe(`responsive layout at ${breakpoint.width}px`, () => {
    test.use({ viewport: { width: breakpoint.width, height: breakpoint.height } });

    for (const [name, path] of [
      ["populated", POPULATED],
      ["empty", EMPTY],
      ["errors", ERRORS],
    ] as const) {
      test(`${name}: no horizontal scroll and nothing spills out of a card`, async ({ page }) => {
        await page.goto(path);
        await expect(page.getByTestId("card-moderation")).toBeVisible();
        // Let the KPI count-up finish so the widest number is on screen.
        await page.waitForTimeout(1500);

        expect(await pageOverflow(page), "page overflow (px)").toBeLessThanOrEqual(0);
        expect(await overflowingCards(page), "cards whose content overflows").toEqual([]);
      });
    }
  });
}

test.describe("on a phone", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("cards stack into a single full-width column", async ({ page }) => {
    await page.goto(POPULATED);
    const boxes = await Promise.all(CARDS.map((id) => page.getByTestId(id).boundingBox()));
    const lefts = new Set(boxes.map((box) => Math.round(box!.x)));
    expect(lefts.size, "all cards share one left edge").toBe(1);
    for (const box of boxes) expect(box!.width).toBeGreaterThan(390 - 2 * 16 - 2);
  });
});

test.describe("motion", () => {
  test("counts the KPIs up from zero by default", async ({ page }) => {
    await recordKpiValues(page);
    await page.goto(POPULATED);
    await expect(page.getByTestId("kpi-total-users")).toContainText("1,842");

    // Dozens of intermediate frames, not a jump.
    expect((await seenKpiValues(page)).length).toBeGreaterThan(5);
  });

  test("animates in and lifts on hover by default", async ({ page }) => {
    await page.goto(POPULATED);
    const card = page.getByTestId("card-booking-value");

    expect(await card.evaluate((el) => getComputedStyle(el).animationName)).not.toBe("none");
    expect(await page.locator(".dash-bar-y").first().evaluate((el) => getComputedStyle(el).animationName)).not.toBe(
      "none",
    );

    // Wait out the staggered entrance, then hover: the card rises 5px.
    await page.waitForTimeout(1600);
    await card.hover();
    await expect
      .poll(() => card.evaluate((el) => getComputedStyle(el).transform), { timeout: 3000 })
      .toBe("matrix(1, 0, 0, 1, 0, -5)");
  });

  test.describe("with reduced motion", () => {
    test.use({ reducedMotion: "reduce" });

    test("turns off every entrance animation and the hover lift", async ({ page }) => {
      const errors = trackConsoleErrors(page);
      await page.goto(POPULATED);
      const card = page.getByTestId("card-booking-value");

      for (const selector of [".dash-reveal", ".dash-bar-y", ".dash-bar-x"]) {
        const names = await page
          .locator(selector)
          .evaluateAll((els) => els.map((el) => getComputedStyle(el).animationName));
        expect(names.length, selector).toBeGreaterThan(0);
        expect(new Set(names), selector).toEqual(new Set(["none"]));
      }

      await card.hover();
      await page.waitForTimeout(400);
      expect(await card.evaluate((el) => getComputedStyle(el).transform)).toBe("none");
      expect(errors, "console errors").toEqual([]);
    });

    test("shows the final KPI value without counting up to it, and hydrates cleanly", async ({ page }) => {
      // Regression guard: reading the preference during the first client render
      // used to make hydration disagree with the server-rendered 0 (a console error).
      const errors = trackConsoleErrors(page);
      await recordKpiValues(page);
      await page.goto(POPULATED);
      await expect(page.getByTestId("kpi-total-users")).toContainText("1,842");
      await page.waitForTimeout(1500);

      // The server-rendered 0, then the final value — never a number in between.
      expect((await seenKpiValues(page)).filter((value) => value !== "0")).toEqual(["1,842"]);
      expect(errors, "console errors").toEqual([]);
    });
  });
});

test.describe("backdrop", () => {
  test("the scene image the glass blurs is served", async ({ request }) => {
    const response = await request.get("/admin/dashboard-scene.svg");
    expect(response.ok()).toBe(true);
    expect(response.headers()["content-type"]).toContain("image/svg+xml");
  });
});
