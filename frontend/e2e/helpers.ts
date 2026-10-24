import { setupClerkTestingToken } from "@clerk/testing/playwright";
import { expect, type Page } from "@playwright/test";

// Clerk development instances accept this code for +clerk_test email addresses.
export const TEST_CODE = "424242";

export function uniqueEmail(prefix: string) {
  return `${prefix}-${Date.now()}-${Math.floor(Math.random() * 1e6)}+clerk_test@example.com`;
}

async function enterEmail(page: Page, email: string) {
  await page.getByLabel("Email address").fill(email);
  await page.getByRole("button", { name: "Continue", exact: true }).click();
}

async function enterCode(page: Page, code: string) {
  await expect(page.getByText(/verification code|check your email/i).first()).toBeVisible();
  await page.keyboard.type(code);
}

export async function expectDashboardFor(page: Page, email: string) {
  await expect(page).toHaveURL(/\/dashboard$/);
  await expect(page.getByRole("heading", { name: `Welcome back, ${email}` })).toBeVisible();
}

export async function signUp(page: Page, email: string) {
  await setupClerkTestingToken({ page });
  await page.goto("/register");
  await enterEmail(page, email);
  await enterCode(page, TEST_CODE);
  await expectDashboardFor(page, email);
}

export async function signIn(page: Page, email: string, code: string = TEST_CODE) {
  await setupClerkTestingToken({ page });
  await page.goto("/login");
  await enterEmail(page, email);
  await enterCode(page, code);
}

export async function signUpNewUser(page: Page, prefix: string) {
  const email = uniqueEmail(prefix);
  await signUp(page, email);
  return email;
}
