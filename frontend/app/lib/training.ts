// The numbers the review pages show, worked out the same way as the iPhone app
// (ios/IronSageKit/Sources/IronSageCore), so both agree. Pure functions, no React.

export type WeightUnit = "kg" | "lb";
export type LoadType = "total" | "per_side" | "bodyweight_plus" | "assisted";
export type SetType = "warmup" | "working" | "drop" | "failure";

export interface TrainingSet {
  set_type: SetType;
  reps?: number | null;
  weight_kg?: number | null;
  rir?: number | null;
  completed_at?: string | null;
}

export interface TrainingWorkout {
  id: string;
  title: string;
  started_at: string;
  ended_at?: string | null;
  exercises: { exercise_id: string; sets: TrainingSet[] }[];
}

export interface Measurement {
  measured_at: string;
  kind: string;
  value: number;
}

export interface Point {
  date: Date;
  value: number;
}

const KILOGRAMS_PER_POUND = 0.45359237;
const DAY = 86_400_000;

export function toUnit(kilograms: number, unit: WeightUnit): number {
  return unit === "kg" ? kilograms : kilograms / KILOGRAMS_PER_POUND;
}

/** "60", "61.25", "135", "132.3": kilograms to two decimals, pounds to one. */
export function formatWeight(kilograms: number, unit: WeightUnit, locale: string): string {
  return toUnit(kilograms, unit).toLocaleString(locale, {
    maximumFractionDigits: unit === "kg" ? 2 : 1,
  });
}

/** Completed sets that count: not warm-ups. */
export function workingSets(sets: TrainingSet[]): TrainingSet[] {
  return sets.filter((set) => set.completed_at && set.set_type !== "warmup");
}

export function isFinished(workout: TrainingWorkout): boolean {
  return Boolean(workout.ended_at);
}

/** The Epley estimate, for 1 to 12 reps with weight; one rep is the weight itself. */
export function estimatedOneRepMax(weightKg: number, reps: number): number | null {
  if (weightKg <= 0 || reps < 1 || reps > 12) return null;
  return reps === 1 ? weightKg : weightKg * (1 + reps / 30);
}

/**
 * Weight × reps of the completed working sets. One dumbbell per side counts twice;
 * assisted sets count nothing.
 */
export function volumeKg(workout: TrainingWorkout, loadTypes: Map<string, LoadType>): number {
  let total = 0;
  for (const item of workout.exercises) {
    const loadType = loadTypes.get(item.exercise_id);
    const factor = loadType === "per_side" ? 2 : loadType === "assisted" ? 0 : 1;
    for (const set of workingSets(item.sets)) {
      total += (set.weight_kg ?? 0) * (set.reps ?? 0) * factor;
    }
  }
  return total;
}

/** Midnight at the start of the week containing `date`, in local time. */
export function startOfWeek(date: Date, weekStartsOn: number): Date {
  const start = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const back = (start.getDay() - weekStartsOn + 7) % 7;
  start.setDate(start.getDate() - back);
  return start;
}

function addWeeks(date: Date, weeks: number): Date {
  const next = new Date(date);
  next.setDate(next.getDate() + weeks * 7);
  return next;
}

/** Finished workouts in the week containing `now`. */
export function workoutsThisWeek(
  workouts: TrainingWorkout[],
  now: Date,
  weekStartsOn: number,
): number {
  const start = startOfWeek(now, weekStartsOn).getTime();
  const end = addWeeks(new Date(start), 1).getTime();
  return workouts.filter((workout) => {
    const time = new Date(workout.started_at).getTime();
    return isFinished(workout) && time >= start && time < end;
  }).length;
}

/**
 * Weeks in a row with a finished workout, counted back from this week. This week
 * counts once trained in; until then the streak runs up to last week.
 */
export function weekStreak(workouts: TrainingWorkout[], now: Date, weekStartsOn: number): number {
  const trained = new Set(
    workouts
      .filter(isFinished)
      .map((workout) => startOfWeek(new Date(workout.started_at), weekStartsOn).getTime()),
  );
  let week = startOfWeek(now, weekStartsOn);
  if (!trained.has(week.getTime())) week = addWeeks(week, -1);
  let streak = 0;
  while (trained.has(week.getTime())) {
    streak += 1;
    week = addWeeks(week, -1);
  }
  return streak;
}

/** Volume of each of the last `count` weeks, oldest first, weeks without training included. */
export function weeklyVolume(
  workouts: TrainingWorkout[],
  loadTypes: Map<string, LoadType>,
  count: number,
  now: Date,
  weekStartsOn: number,
): { start: Date; kilograms: number }[] {
  const current = startOfWeek(now, weekStartsOn);
  const weeks = Array.from({ length: count }, (_, index) => addWeeks(current, index - count + 1));
  const volume = new Map<number, number>();
  for (const workout of workouts.filter(isFinished)) {
    const start = startOfWeek(new Date(workout.started_at), weekStartsOn).getTime();
    volume.set(start, (volume.get(start) ?? 0) + volumeKg(workout, loadTypes));
  }
  return weeks.map((start) => ({ start, kilograms: volume.get(start.getTime()) ?? 0 }));
}

export type Range = "week" | "month" | "year" | "all";

/** The first moment a range shows, or null for everything. */
export function rangeStart(range: Range, now: Date): Date | null {
  const start = new Date(now);
  switch (range) {
    case "week":
      start.setDate(start.getDate() - 7);
      return start;
    case "month":
      start.setMonth(start.getMonth() - 1);
      return start;
    case "year":
      start.setFullYear(start.getFullYear() - 1);
      return start;
    case "all":
      return null;
  }
}

/** Over more than this many days, body charts show one average per week. */
export const WEEKLY_AFTER_DAYS = 120;

/**
 * Measurements of one kind in the range, oldest first; one per week (the week's
 * average, at its average time) once they span more than WEEKLY_AFTER_DAYS days.
 */
export function bodyPoints(
  measurements: Measurement[],
  kind: string,
  range: Range,
  now: Date,
  weekStartsOn: number,
): Point[] {
  const start = rangeStart(range, now)?.getTime() ?? -Infinity;
  const points = measurements
    .filter((measurement) => measurement.kind === kind)
    .map((measurement) => ({ date: new Date(measurement.measured_at), value: measurement.value }))
    .filter((point) => point.date.getTime() >= start && point.date.getTime() <= now.getTime())
    .sort((a, b) => a.date.getTime() - b.date.getTime());
  if (points.length < 2) return points;
  const span = points[points.length - 1].date.getTime() - points[0].date.getTime();
  if (span <= WEEKLY_AFTER_DAYS * DAY) return points;

  const weeks = new Map<number, Point[]>();
  for (const point of points) {
    const week = startOfWeek(point.date, weekStartsOn).getTime();
    weeks.set(week, [...(weeks.get(week) ?? []), point]);
  }
  return [...weeks.keys()]
    .sort((a, b) => a - b)
    .map((week) => {
      const inWeek = weeks.get(week)!;
      const time = inWeek.reduce((sum, point) => sum + point.date.getTime(), 0) / inWeek.length;
      const value = inWeek.reduce((sum, point) => sum + point.value, 0) / inWeek.length;
      return { date: new Date(time), value };
    });
}

/** The most recent measurement of one kind. */
export function latest(measurements: Measurement[], kind: string): Measurement | undefined {
  return measurements
    .filter((measurement) => measurement.kind === kind)
    .reduce<Measurement | undefined>(
      (newest, measurement) =>
        !newest || measurement.measured_at > newest.measured_at ? measurement : newest,
      undefined,
    );
}

export interface Lift {
  weightKg: number;
  reps: number;
  date: Date;
}

export interface Session {
  workoutId: string;
  date: Date;
  sets: TrainingSet[];
  estimatedOneRepMax: number | null;
}

/** Each finished workout with completed working sets of the exercise, newest first. */
export function exerciseSessions(workouts: TrainingWorkout[], exerciseId: string): Session[] {
  return workouts
    .filter(isFinished)
    .flatMap((workout) => {
      const sets = workout.exercises
        .filter((item) => item.exercise_id === exerciseId)
        .flatMap((item) => workingSets(item.sets));
      if (sets.length === 0) return [];
      const estimates = sets
        .map((set) => estimatedOneRepMax(set.weight_kg ?? 0, set.reps ?? 0))
        .filter((estimate): estimate is number => estimate !== null);
      return [
        {
          workoutId: workout.id,
          date: new Date(workout.started_at),
          sets,
          estimatedOneRepMax: estimates.length ? Math.max(...estimates) : null,
        },
      ];
    })
    .sort((a, b) => b.date.getTime() - a.date.getTime());
}

/**
 * The heaviest set and the set with the best estimated one-rep max. Ties keep the
 * earliest, the day the record was set. Assisted exercises have no weight records,
 * since less assistance is the harder set.
 */
export function records(
  sessions: Session[],
  loadType: LoadType | undefined,
): { heaviest?: Lift; bestEstimate?: Lift & { estimateKg: number } } {
  if (loadType === "assisted") return {};
  let heaviest: Lift | undefined;
  let bestEstimate: (Lift & { estimateKg: number }) | undefined;
  for (const session of [...sessions].sort((a, b) => a.date.getTime() - b.date.getTime())) {
    for (const set of session.sets) {
      const weightKg = set.weight_kg ?? 0;
      const reps = set.reps ?? 0;
      if (weightKg <= 0 || reps <= 0) continue;
      const lift = { weightKg, reps, date: session.date };
      if (!heaviest || weightKg > heaviest.weightKg + 0.0005) heaviest = lift;
      const estimateKg = estimatedOneRepMax(weightKg, reps);
      if (estimateKg !== null && (!bestEstimate || estimateKg > bestEstimate.estimateKg + 0.0005)) {
        bestEstimate = { ...lift, estimateKg };
      }
    }
  }
  return { heaviest, bestEstimate };
}

/** Exercises done in finished workouts, most recently done first. */
export function recentExercises(workouts: TrainingWorkout[]): string[] {
  const seen = new Set<string>();
  const order: string[] = [];
  const newestFirst = workouts
    .filter(isFinished)
    .sort((a, b) => new Date(b.started_at).getTime() - new Date(a.started_at).getTime());
  for (const workout of newestFirst) {
    for (const item of workout.exercises) {
      if (workingSets(item.sets).length && !seen.has(item.exercise_id)) {
        seen.add(item.exercise_id);
        order.push(item.exercise_id);
      }
    }
  }
  return order;
}
