import { setupClerkTestingToken } from "@clerk/testing/playwright";
import { expect, test } from "@playwright/test";

import { API_URL, sessionToken, signUp, signUpNewUser } from "./helpers";

test("landing page introduces the app and links to sign-in", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("img", { name: "IronSage" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Know what to lift next." })).toBeVisible();
  await page.getByRole("link", { name: "Sign in" }).click();
  await expect(page).toHaveURL(/\/login/);
});

test("user can delete their account", async ({ page }) => {
  const email = await signUpNewUser(page, "delete");

  await page.getByRole("button", { name: "Delete account" }).click();
  await page.getByRole("button", { name: "Yes, delete everything" }).click();
  await expect(page).not.toHaveURL(/\/account/);

  // The Clerk user is gone too, so signing in with the same email no longer works.
  await page.goto("/login");
  await setupClerkTestingToken({ page });
  await page.getByLabel("Email address").fill(email);
  await page.getByRole("button", { name: "Continue", exact: true }).click();
  await expect(page.getByText("Couldn't find your account.").first()).toBeVisible();
});

test("deleting the account removes the data the app saved", async ({ page, request }) => {
  const email = await signUpNewUser(page, "delete-data");

  // The iPhone app saves a workout and a night through the API with the same session.
  const auth = { Authorization: `Bearer ${await sessionToken(page)}` };
  const workout = {
    title: "Push day",
    started_at: "2026-10-20T18:00:00Z",
    ended_at: "2026-10-20T19:00:00Z",
    time_zone: "America/New_York",
    exercises: [],
  };
  const saved = await request.put(`${API_URL}/v1/workouts/${crypto.randomUUID()}`, {
    headers: auth,
    data: workout,
  });
  expect(saved.ok()).toBeTruthy();
  const night = await request.put(`${API_URL}/v1/readiness/2026-10-21`, {
    headers: auth,
    data: { sleep_minutes: 420 },
  });
  expect(night.ok()).toBeTruthy();

  await page.getByRole("button", { name: "Delete account" }).click();
  await page.getByRole("button", { name: "Yes, delete everything" }).click();
  await expect(page).not.toHaveURL(/\/account/);

  // Signing up again with the same email starts an empty account.
  await signUp(page, email);
  const sync = await request.get(`${API_URL}/v1/sync?since=0`, {
    headers: { Authorization: `Bearer ${await sessionToken(page)}` },
  });
  expect(sync.ok()).toBeTruthy();
  const changes = await sync.json();
  expect(changes.workouts).toEqual([]);
  expect(changes.readiness).toEqual([]);
});

test("sign-in follows the system's dark mode", async ({ page }) => {
  await page.emulateMedia({ colorScheme: "dark" });
  await page.goto("/login");
  const card = page.locator(".cl-card").first();
  await expect(card).toBeVisible();
  const background = await card.evaluate((element) => getComputedStyle(element).backgroundColor);
  const [red, green, blue] = (background.match(/\d+(\.\d+)?/g) ?? []).map(Number);
  // A dark card, not the light one on a dark page.
  expect(0.2126 * red + 0.7152 * green + 0.0722 * blue).toBeLessThan(100);
});

test("privacy policy and support pages are linked and available in Chinese", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("link", { name: "Privacy" }).click();
  await expect(page.getByRole("heading", { name: "Privacy policy" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "The AI coach" })).toBeVisible();
  await page.getByRole("link", { name: "中文" }).click();
  await expect(page.getByRole("heading", { name: "隐私政策" })).toBeVisible();

  await page.goto("/");
  await page.getByRole("link", { name: "Support" }).click();
  await expect(page.getByRole("heading", { name: "Support" })).toBeVisible();
  await expect(page.getByText("support@ironsage.app").first()).toBeVisible();
});
