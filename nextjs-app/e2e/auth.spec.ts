import { test, expect } from "@playwright/test";

/**
 * Step 5 authentication — each Playwright project starts with a fresh,
 * cookie-less browser context, so every test here is a genuine zero-session
 * visit without needing to explicitly clear anything first.
 */

test.describe("/auth", () => {
  test("renders both provider sign-in buttons", async ({ page }) => {
    await page.goto("/auth?redirect=%2Fprofile%2Foverview");

    await expect(page.getByRole("button", { name: "Continue with Google" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Continue with GitHub" })).toBeVisible();
  });

  test("shows the identity_already_exists recovery action instead of the plain buttons", async ({
    page,
  }) => {
    await page.goto(
      "/auth?redirect=%2Fprofile%2Foverview&error=identity_already_exists&provider=google",
    );

    await expect(
      page.getByRole("button", { name: "Sign in with this Google account" }),
    ).toBeVisible();
    await expect(page.getByRole("button", { name: "Continue with Google" })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Continue with GitHub" })).toHaveCount(0);
  });
});

test.describe("requireRealUserOrRedirect", () => {
  test("a no-session visit to a protected page redirects to /auth with the right ?redirect=", async ({
    page,
  }) => {
    await page.goto("/dev-preview/protected");

    await expect(page).toHaveURL("/auth?redirect=%2Fdev-preview%2Fprotected");
  });
});

test.describe("guest profile view", () => {
  test("a no-session visit to /profile/overview renders the guest view, not a crash or redirect", async ({
    page,
  }) => {
    const response = await page.goto("/profile/overview");

    expect(response?.status()).toBe(200);
    await expect(page).toHaveURL("/profile/overview");
    await expect(page.getByRole("link", { name: "Sign in" })).toBeVisible();
  });
});
