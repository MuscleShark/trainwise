"use client";

import { formatWeight, startOfWeek, volumeKg, workingSets, type TrainingSet } from "../../lib/training";
import { useReview } from "../data";
import { fullDay, weekRange } from "../format";

/** Every workout by week, newest first; each opens to its exercises and sets. */
export default function HistoryPage() {
  const { training, t, locale, weekStartsOn } = useReview();
  if (!training) return null;

  const weeks = new Map<number, typeof training.workouts>();
  for (const workout of training.workouts) {
    const week = startOfWeek(new Date(workout.started_at), weekStartsOn).getTime();
    weeks.set(week, [...(weeks.get(week) ?? []), workout]);
  }

  return (
    <>
      <h1 className="type-stamp text-4xl sm:text-5xl">{t.history}</h1>
      {weeks.size === 0 ? <p className="mt-6 max-w-xl leading-relaxed text-steel">{t.noWorkouts}</p> : null}
      {[...weeks.entries()].map(([week, workouts]) => (
        <section key={week} className="mt-10">
          <h2 className="text-sm font-medium text-steel">{t.weekOf(weekRange(new Date(week), locale))}</h2>
          <ul className="mt-3 space-y-2">
            {workouts.map((workout) => {
              const started = new Date(workout.started_at);
              const minutes = workout.ended_at
                ? Math.round((new Date(workout.ended_at).getTime() - started.getTime()) / 60_000)
                : null;
              const sets = workout.exercises.reduce((sum, item) => sum + workingSets(item.sets).length, 0);
              return (
                <li key={workout.id}>
                  <details className="group rounded-sm bg-card">
                    <summary className="flex cursor-pointer list-none flex-wrap items-baseline justify-between gap-x-6 gap-y-1 px-4 py-3 marker:hidden">
                      <span className="flex items-baseline gap-2 font-medium">
                        <span aria-hidden className="inline-block text-steel transition-transform group-open:rotate-90">
                          ›
                        </span>
                        {workout.title}
                      </span>
                      <span className="text-sm text-steel tabular-nums">
                        {fullDay(started, locale)} · {minutes === null ? t.inProgress : t.minutes(minutes)} ·{" "}
                        {t.sets(sets)} · {formatWeight(volumeKg(workout, training.loadTypes), training.unit, locale)}{" "}
                        {training.unit}
                      </span>
                    </summary>
                    <div className="space-y-4 border-t border-ink/10 px-4 py-4">
                      {workout.exercises.map((item) => (
                        <ExerciseSets key={item.id} exerciseId={item.exercise_id} sets={item.sets} />
                      ))}
                    </div>
                  </details>
                </li>
              );
            })}
          </ul>
        </section>
      ))}
    </>
  );
}

function ExerciseSets({ exerciseId, sets }: { exerciseId: string; sets: TrainingSet[] }) {
  const { training, t, locale, exerciseName } = useReview();
  if (!training) return null;
  const done = sets.filter((set) => set.completed_at);
  if (done.length === 0) return null;

  return (
    <div>
      <h3 className="font-medium">{exerciseName(exerciseId)}</h3>
      <ol className="mt-1.5 space-y-0.5 text-sm tabular-nums">
        {done.map((set, index) => {
          const tag = set.set_type === "warmup" ? t.warmup : set.set_type === "drop" ? t.drop : set.set_type === "failure" ? t.failure : null;
          const weight = set.weight_kg ? `${formatWeight(set.weight_kg, training.unit, locale)} ${training.unit} × ` : "";
          return (
            <li key={index} className={`flex gap-3 ${set.set_type === "warmup" ? "text-steel" : ""}`}>
              <span className="w-5 text-right text-steel">{index + 1}</span>
              <span>
                {weight}
                {set.reps ?? "–"}
              </span>
              {typeof set.rir === "number" ? <span className="text-steel">{t.rir(set.rir)}</span> : null}
              {tag ? <span className="text-steel">{tag}</span> : null}
            </li>
          );
        })}
      </ol>
    </div>
  );
}
