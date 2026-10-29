// Run with `npm test` (Node's own test runner; Node strips the types).
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  bodyPoints,
  estimatedOneRepMax,
  exerciseSessions,
  formatWeight,
  type LoadType,
  type Measurement,
  recentExercises,
  records,
  type TrainingSet,
  type TrainingWorkout,
  volumeKg,
  weeklyVolume,
  weekStreak,
  workoutsThisWeek,
} from "./training.ts";

const MONDAY = 1;
const BENCH = "bench";
const CURL = "curl";
const loadTypes = new Map<string, LoadType>([
  [BENCH, "total"],
  [CURL, "per_side"],
]);

/** Monday 2 November 2026 at noon local time, plus `days`. */
function day(days: number): Date {
  return new Date(2026, 10, 2 + days, 12);
}

function set(kg: number, reps: number, options: { done?: boolean; warmup?: boolean } = {}): TrainingSet {
  return {
    set_type: options.warmup ? "warmup" : "working",
    reps,
    weight_kg: kg,
    completed_at: options.done === false ? null : day(0).toISOString(),
  };
}

function workout(
  days: number,
  items: [string, TrainingSet[]][],
  finished = true,
): TrainingWorkout {
  const start = day(days);
  return {
    id: `${days}-${items.map(([id]) => id).join()}`,
    title: "W",
    started_at: start.toISOString(),
    ended_at: finished ? new Date(start.getTime() + 3_600_000).toISOString() : null,
    exercises: items.map(([exercise_id, sets]) => ({ exercise_id, sets })),
  };
}

test("weights show in the user's unit with the app's decimals", () => {
  assert.equal(formatWeight(61.25, "kg", "en-US"), "61.25");
  assert.equal(formatWeight(60, "lb", "en-US"), "132.3");
  assert.equal(formatWeight(1000, "kg", "en-US"), "1,000");
});

test("the one-rep max estimate covers 1 to 12 reps", () => {
  assert.equal(estimatedOneRepMax(100, 1), 100);
  assert.equal(estimatedOneRepMax(100, 6), 120);
  assert.equal(estimatedOneRepMax(100, 13), null);
  assert.equal(estimatedOneRepMax(0, 5), null);
});

test("volume counts completed working sets, one dumbbell per side twice", () => {
  const session = workout(0, [
    [BENCH, [set(100, 5), set(60, 10, { warmup: true }), set(100, 5, { done: false })]],
    [CURL, [set(10, 10)]],
  ]);
  assert.equal(volumeKg(session, loadTypes), 700);
});

test("this week counts finished workouts in it", () => {
  const workouts = [
    workout(0, [[BENCH, [set(100, 5)]]]),
    workout(2, [[BENCH, [set(100, 5)]]]),
    workout(3, [[BENCH, [set(100, 5)]]], false),
    workout(-1, [[BENCH, [set(100, 5)]]]),
  ];
  assert.equal(workoutsThisWeek(workouts, day(3), MONDAY), 2);
});

test("the streak counts weeks in a row and holds until this week ends", () => {
  const workouts = [
    workout(1, [[BENCH, [set(100, 5)]]]),
    workout(-6, [[BENCH, [set(100, 5)]]]),
    workout(-13, [[BENCH, [set(100, 5)]]]),
    workout(-27, [[BENCH, [set(100, 5)]]]),
  ];
  assert.equal(weekStreak(workouts, day(2), MONDAY), 3);
  assert.equal(weekStreak(workouts.slice(1), day(2), MONDAY), 2);
  assert.equal(weekStreak(workouts.slice(1), day(9), MONDAY), 0);
  assert.equal(weekStreak([], day(2), MONDAY), 0);
});

test("weekly volume includes weeks without training, oldest first", () => {
  const volume = weeklyVolume(
    [
      workout(1, [[BENCH, [set(100, 5)]]]),
      workout(-6, [[CURL, [set(10, 10)]]]),
      workout(-20, [[BENCH, [set(100, 1)]]]),
    ],
    loadTypes,
    3,
    day(2),
    MONDAY,
  );
  assert.deepEqual(
    volume.map((week) => week.kilograms),
    [0, 200, 500],
  );
  assert.equal(volume[2].start.getTime(), new Date(2026, 10, 2).getTime());
});

function fat(days: number, value: number): Measurement {
  return { measured_at: day(days).toISOString(), kind: "body_fat", value };
}

test("body points show one kind in the range, oldest first", () => {
  const measurements = [
    fat(-1, 18),
    fat(-10, 19),
    fat(-40, 20),
    { measured_at: day(-2).toISOString(), kind: "weight", value: 80 },
  ];
  const values = (range: "week" | "month" | "all") =>
    bodyPoints(measurements, "body_fat", range, day(0), MONDAY).map((point) => point.value);
  assert.deepEqual(values("week"), [18]);
  assert.deepEqual(values("month"), [19, 18]);
  assert.deepEqual(values("all"), [20, 19, 18]);
});

test("body points average each week over long spans", () => {
  const points = bodyPoints(
    [fat(-196, 20), fat(-194, 22), fat(0, 18)],
    "body_fat",
    "year",
    day(1),
    MONDAY,
  );
  assert.deepEqual(
    points.map((point) => point.value),
    [21, 18],
  );
  assert.equal(points[0].date.getTime(), day(-195).getTime());
});

test("records keep the earliest heaviest and best estimated sets", () => {
  const workouts = [
    workout(-7, [[BENCH, [set(100, 5), set(100, 5)]]]),
    workout(0, [[BENCH, [set(100, 3), set(90, 10, { warmup: true })]]]),
    workout(1, [[CURL, [set(12, 10)]]]),
  ];
  const sessions = exerciseSessions(workouts, BENCH);
  assert.equal(sessions.length, 2);
  assert.equal(sessions[0].date.getTime(), day(0).getTime());
  assert.equal(sessions[1].estimatedOneRepMax?.toFixed(2), "116.67");

  const best = records(sessions, "total");
  assert.equal(best.heaviest?.date.getTime(), day(-7).getTime());
  assert.equal(best.bestEstimate?.reps, 5);
  assert.deepEqual(records(sessions, "assisted"), {});
});

test("recent exercises come newest first", () => {
  const order = recentExercises([
    workout(0, [[BENCH, [set(80, 5)]]]),
    workout(2, [[CURL, [set(12, 10)]]]),
    workout(3, [[BENCH, [set(80, 5, { done: false })]]]),
  ]);
  assert.deepEqual(order, [CURL, BENCH]);
});
