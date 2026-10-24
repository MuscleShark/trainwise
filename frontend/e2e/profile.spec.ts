import { expect, test } from "@playwright/test";

import { signUpNewUser } from "./helpers";

test("user can create and update a profile", async ({ page }) => {
  await signUpNewUser(page, "profile");

  await page.getByRole("link", { name: "Manage profile" }).click();
  await expect(page).toHaveURL(/\/profile$/);

  await page.getByLabel("Height (cm)").fill("180");
  await page.getByLabel("Weight (kg)").fill("75");
  await page.getByLabel("Fitness goal").selectOption("build muscle");
  await page.getByLabel("Training location").selectOption("gym");
  await page.getByRole("button", { name: "Create profile" }).click();
  await expect(page.getByRole("status")).toHaveText(
    "Your profile has been saved.",
  );

  await page.reload();
  await expect(page.getByLabel("Height (cm)")).toHaveValue("180");
  await expect(page.getByLabel("Fitness goal")).toHaveValue("build muscle");

  await page.getByLabel("Weight (kg)").fill("72.5");
  await page.getByRole("button", { name: "Save changes" }).click();
  await expect(page.getByRole("status")).toHaveText(
    "Your profile has been saved.",
  );

  await page.reload();
  await expect(page.getByLabel("Weight (kg)")).toHaveValue("72.5");
});
