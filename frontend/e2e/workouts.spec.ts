import { expect, test } from "@playwright/test";

import { registerAndLogin } from "./helpers";

test("user can add, edit and delete a workout", async ({ page }) => {
  await registerAndLogin(page, "workouts");

  await page.getByRole("link", { name: "View workouts" }).click();
  await expect(page).toHaveURL(/\/workouts$/);
  await expect(page.getByText("No workouts yet.")).toBeVisible();

  await page.getByLabel("Date").fill("2026-09-23");
  await page.getByLabel("Workout type").fill("Strength");
  await page.getByLabel("Duration (minutes)").fill("60");
  await page.getByLabel("Notes").fill("Upper-body session");
  await page.getByRole("button", { name: "Add workout" }).click();

  const card = page.getByRole("article").filter({ hasText: "Strength" });
  await expect(card).toContainText("60 minutes");
  await expect(card).toContainText("Upper-body session");

  // Data must come back from the API, not just local state.
  await page.reload();
  await expect(card).toContainText("60 minutes");

  await card.getByRole("button", { name: "Edit" }).click();
  await page.getByLabel("Duration (minutes)").fill("75");
  await page.getByRole("button", { name: "Save changes" }).click();
  await expect(card).toContainText("75 minutes");

  page.once("dialog", (dialog) => dialog.accept());
  await card.getByRole("button", { name: "Delete" }).click();
  await expect(page.getByText("No workouts yet.")).toBeVisible();
});

test("users only see their own workouts", async ({ browser }) => {
  const ownerContext = await browser.newContext();
  const owner = await ownerContext.newPage();
  await registerAndLogin(owner, "owner");
  await owner.goto("/workouts");
  await owner.getByLabel("Date").fill("2026-09-23");
  await owner.getByLabel("Workout type").fill("Owner only cardio");
  await owner.getByLabel("Duration (minutes)").fill("30");
  await owner.getByRole("button", { name: "Add workout" }).click();
  await expect(owner.getByText("Owner only cardio")).toBeVisible();

  const otherContext = await browser.newContext();
  const other = await otherContext.newPage();
  await registerAndLogin(other, "other");
  await other.goto("/workouts");
  await expect(other.getByText("No workouts yet.")).toBeVisible();
  await expect(other.getByText("Owner only cardio")).toHaveCount(0);

  await ownerContext.close();
  await otherContext.close();
});
