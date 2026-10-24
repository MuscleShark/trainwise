import { expect, test } from "@playwright/test";

import { expectDashboardFor, signIn, signUpNewUser } from "./helpers";

test("protected pages redirect to login when signed out", async ({ page }) => {
  for (const path of ["/dashboard", "/workouts", "/profile"]) {
    await page.goto(path);
    await expect(page).toHaveURL(/\/login/);
  }
});

// Google and Apple sign-in go through real provider pages, so E2E only checks the
// buttons are offered; the full OAuth flows are checked by hand.
for (const path of ["/login", "/register"]) {
  test(`${path} offers Google and Apple sign-in`, async ({ page }) => {
    await page.goto(path);
    await expect(page.getByRole("button", { name: /google/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /apple/i })).toBeVisible();
  });
}

test("user can sign up with an email code, sign out and sign back in", async ({ page }) => {
  const email = await signUpNewUser(page, "auth");

  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page).toHaveURL(/\/login/);

  await page.goto("/dashboard");
  await expect(page).toHaveURL(/\/login/);

  await signIn(page, email);
  await expectDashboardFor(page, email);
});

test("a wrong email code is rejected", async ({ page }) => {
  const email = await signUpNewUser(page, "wrong-code");
  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page).toHaveURL(/\/login/);

  await signIn(page, email, "000000");

  await expect(page.getByText(/incorrect|invalid/i).first()).toBeVisible();
  await expect(page).not.toHaveURL(/\/dashboard/);
});
