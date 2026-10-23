import { expect, test } from "@playwright/test";

import { registerAndLogin } from "./helpers";

test("protected pages redirect to login when signed out", async ({ page }) => {
  for (const path of ["/dashboard", "/workouts", "/profile"]) {
    await page.goto(path);
    await expect(page).toHaveURL(/\/login$/);
  }
});

test("user can register, sign in and sign out", async ({ page }) => {
  await registerAndLogin(page, "auth");

  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page).toHaveURL(/\/login$/);

  await page.goto("/dashboard");
  await expect(page).toHaveURL(/\/login$/);
});

test("login shows an error for a wrong password", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("Email").fill("nobody@example.com");
  await page.getByLabel("Password").fill("WrongPassword123!");
  await page.getByRole("button", { name: "Sign in" }).click();

  // Next.js also renders an empty role="alert" route announcer, so match the message text.
  await expect(
    page.getByRole("alert").filter({ hasText: "Invalid email or password" }),
  ).toBeVisible();
  await expect(page).toHaveURL(/\/login$/);
});
