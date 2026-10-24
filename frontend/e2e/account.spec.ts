import { setupClerkTestingToken } from "@clerk/testing/playwright";
import { expect, test } from "@playwright/test";

import { signUpNewUser } from "./helpers";

test("landing page introduces the app and links to sign-in", async ({ page }) => {
  await page.goto("/");
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
