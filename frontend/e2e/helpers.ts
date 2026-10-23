import { expect, type Page } from "@playwright/test";

export const PASSWORD = "StrongPassword123!";

export function uniqueEmail(prefix: string) {
  return `${prefix}-${Date.now()}-${Math.floor(Math.random() * 1e6)}@example.com`;
}

export async function register(page: Page, email: string) {
  await page.goto("/register");
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password", { exact: true }).fill(PASSWORD);
  await page.getByLabel("Confirm password").fill(PASSWORD);
  await page.getByRole("button", { name: "Create account" }).click();
  await expect(page).toHaveURL(/\/login$/);
}

export async function login(page: Page, email: string) {
  await page.goto("/login");
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(PASSWORD);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).toHaveURL(/\/dashboard$/);
  await expect(
    page.getByRole("heading", { name: `Welcome back, ${email}` }),
  ).toBeVisible();
}

export async function registerAndLogin(page: Page, prefix: string) {
  const email = uniqueEmail(prefix);
  await register(page, email);
  await login(page, email);
  return email;
}
