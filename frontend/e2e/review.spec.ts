import { expect, test } from "@playwright/test";

import { API_URL, sessionToken, signUpNewUser } from "./helpers";

test("the review shows what the app saved, read-only", async ({ page, request }) => {
  await signUpNewUser(page, "review");

  // The iPhone app saves the profile, a workout and a weight through the API.
  const auth = { Authorization: `Bearer ${await sessionToken(page)}` };
  const profile = await request.put(`${API_URL}/v1/profile`, {
    headers: auth,
    data: { unit_system: "metric", training_days_per_week: 3 },
  });
  expect(profile.ok()).toBeTruthy();

  const exercises = await (await request.get(`${API_URL}/v1/exercises`, { headers: auth })).json();
  const bench = exercises.find((exercise: { name_en: string }) => exercise.name_en === "Barbell bench press");
  expect(bench).toBeTruthy();

  const started = new Date(Date.now() - 2 * 3_600_000);
  const done = new Date(started.getTime() + 600_000).toISOString();
  const set = (weight_kg: number, reps: number, set_type = "working") => ({
    id: crypto.randomUUID(),
    set_type,
    weight_kg,
    reps,
    completed_at: done,
  });
  const workout = await request.put(`${API_URL}/v1/workouts/${crypto.randomUUID()}`, {
    headers: auth,
    data: {
      title: "Push day",
      started_at: started.toISOString(),
      ended_at: new Date(started.getTime() + 3_600_000).toISOString(),
      time_zone: "UTC",
      exercises: [
        {
          id: crypto.randomUUID(),
          exercise_id: bench.id,
          sets: [set(40, 10, "warmup"), set(60, 8), set(60, 8)],
        },
      ],
    },
  });
  expect(workout.ok()).toBeTruthy();
  const weight = await request.put(`${API_URL}/v1/body-measurements/${crypto.randomUUID()}`, {
    headers: auth,
    data: { measured_at: started.toISOString(), kind: "weight", value: 80.5, source: "manual" },
  });
  expect(weight.ok()).toBeTruthy();

  await page.goto("/review");
  await expect(page.getByRole("heading", { name: "Your training" })).toBeVisible();
  await expect(page.getByText("1/3")).toBeVisible();
  await expect(page.getByText("80.5 kg")).toBeVisible();
  await expect(page.getByText("Push day")).toBeVisible();
  // Two working sets of 60 × 8; the warm-up doesn't count.
  await expect(page.getByText(/2 sets · 960 kg/)).toBeVisible();

  await page.getByRole("link", { name: "History" }).click();
  await page.getByText("Push day").click();
  await expect(page.getByRole("heading", { name: "Barbell bench press" })).toBeVisible();
  await expect(page.getByText("60 kg × 8").first()).toBeVisible();

  await page.getByRole("link", { name: "Exercises" }).click();
  await expect(page.getByRole("combobox", { name: "Exercise" })).toHaveValue(bench.id);
  // 60 kg × 8 estimates 76 kg.
  await expect(page.getByText("76 kg", { exact: true })).toBeVisible();
  await expect(page.getByText("To change anything, use the IronSage iPhone app.")).toBeVisible();
});
