import { setupClerkTestingToken } from "@clerk/testing/playwright";
import { expect, type Page } from "@playwright/test";

// Clerk development instances accept this code for +clerk_test email addresses.
export const TEST_CODE = "424242";

export function uniqueEmail(prefix: string) {
  return `${prefix}-${Date.now()}-${Math.floor(Math.random() * 1e6)}+clerk_test@example.com`;
}

// Submits the email and waits until Clerk has actually sent the code. Typing the
// code earlier fails with "You need to send a verification code before attempting
// to verify", and the code screen appears before the send has finished.
async function enterEmail(page: Page, email: string) {
  const codeSent = page.waitForResponse(
    (response) =>
      /\/(prepare_verification|prepare_first_factor)/.test(response.url()) && response.ok(),
  );
  await page.getByLabel("Email address").fill(email);
  await page.getByRole("button", { name: "Continue", exact: true }).click();
  await codeSent;
}

async function enterCode(page: Page, code: string) {
  await page.getByRole("textbox", { name: "Enter verification code" }).pressSequentially(code);
}

export async function expectAccountFor(page: Page, email: string) {
  await expect(page).toHaveURL(/\/account$/);
  await expect(page.getByText(`Signed in as ${email}`)).toBeVisible();
}

export async function signUp(page: Page, email: string) {
  await setupClerkTestingToken({ page });
  await page.goto("/register");
  await enterEmail(page, email);
  await enterCode(page, TEST_CODE);
  await expectAccountFor(page, email);
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
