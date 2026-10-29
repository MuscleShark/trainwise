"use client";

import { useState } from "react";

import { exerciseSessions, formatWeight, recentExercises, records, toUnit } from "../../lib/training";
import { LineChart } from "../charts";
import { useReview } from "../data";
import { axisDate, fullDay, shortDay } from "../format";

/** One exercise at a time: its estimated one-rep max over time, records and sessions. */
export default function ExercisesPage() {
  const { training, t, exerciseName } = useReview();
  const [chosen, setChosen] = useState<string | null>(null);
  if (!training) return null;

  const done = recentExercises(training.workouts);
  const exerciseId = chosen && done.includes(chosen) ? chosen : done[0];

  return (
    <>
      <h1 className="type-stamp text-4xl sm:text-5xl">{t.exercises}</h1>
      {exerciseId ? (
        <>
          <label className="mt-6 block max-w-sm">
            <span className="text-sm text-steel">{t.chooseExercise}</span>
            <select
              value={exerciseId}
              onChange={(event) => setChosen(event.target.value)}
              className="mt-1 block w-full rounded-sm border border-ink/20 bg-card px-3 py-2.5 font-medium"
            >
              {done.map((id) => (
                <option key={id} value={id}>
                  {exerciseName(id)}
                </option>
              ))}
            </select>
          </label>
          <ExerciseProgress key={exerciseId} exerciseId={exerciseId} />
        </>
      ) : (
        <p className="mt-6 max-w-xl leading-relaxed text-steel">{t.noExercises}</p>
      )}
    </>
  );
}

function ExerciseProgress({ exerciseId }: { exerciseId: string }) {
  const { training, t, locale, exerciseName } = useReview();
  if (!training) return null;
  const unit = training.unit;
  const loadType = training.loadTypes.get(exerciseId);
  const sessions = exerciseSessions(training.workouts, exerciseId);
  const best = records(sessions, loadType);
  const points = sessions
    .filter((session) => session.estimatedOneRepMax !== null)
    .map((session) => ({ date: session.date, value: toUnit(session.estimatedOneRepMax!, unit) }))
    .reverse();
  const lift = (weightKg: number, reps: number) => `${formatWeight(weightKg, unit, locale)} ${unit} × ${reps}`;

  return (
    <>
      {best.heaviest || best.bestEstimate ? (
        <dl className="mt-8 grid gap-5 sm:grid-cols-2">
          {best.bestEstimate ? (
            <Record
              label={t.bestEstimate}
              value={`${formatWeight(best.bestEstimate.estimateKg, unit, locale)} ${unit}`}
              detail={t.fromLift(lift(best.bestEstimate.weightKg, best.bestEstimate.reps), shortDay(best.bestEstimate.date, locale))}
            />
          ) : null}
          {best.heaviest ? (
            <Record
              label={t.heaviest}
              value={`${formatWeight(best.heaviest.weightKg, unit, locale)} ${unit}`}
              detail={t.fromLift(lift(best.heaviest.weightKg, best.heaviest.reps), shortDay(best.heaviest.date, locale))}
            />
          ) : null}
        </dl>
      ) : null}

      {points.length ? (
        <section className="mt-10">
          <h2 className="text-xl font-semibold">{t.estimatedOneRepMax}</h2>
          <p className="mt-1 text-sm text-steel">{t.estimateNote}</p>
          <div className="mt-5 rounded-sm bg-card p-4 sm:p-5">
            <LineChart
              points={points}
              start={points[0].date}
              end={points[points.length - 1].date}
              title={`${t.estimatedOneRepMax}: ${exerciseName(exerciseId)} (${unit})`}
              dateHeading={t.date}
              formatValue={(value) => value.toLocaleString(locale, { maximumFractionDigits: 1 })}
              formatAxisDate={(date) => axisDate(date, "all", locale)}
              formatDate={(date) => fullDay(date, locale)}
            />
          </div>
        </section>
      ) : null}

      <section className="mt-10">
        <h2 className="text-xl font-semibold">{t.sessions}</h2>
        <ul className="mt-4 divide-y divide-ink/15 border-y border-ink/15">
          {sessions.map((session) => (
            <li key={session.workoutId} className="flex flex-wrap justify-between gap-x-6 gap-y-1 py-3">
              <span className="text-sm text-steel">{fullDay(session.date, locale)}</span>
              <span className="text-sm tabular-nums">
                {session.sets.map((set) => (set.weight_kg ? lift(set.weight_kg, set.reps ?? 0) : `${set.reps ?? "–"}`)).join(", ")}
              </span>
            </li>
          ))}
        </ul>
      </section>
    </>
  );
}

function Record({ label, value, detail }: { label: string; value: string; detail: string }) {
  return (
    <div className="rounded-sm bg-card p-4 sm:p-5">
      <dt className="text-sm text-steel">{label}</dt>
      <dd>
        <span className="type-stamp mt-1 block text-4xl tabular-nums">{value}</span>
        <span className="mt-1 block text-sm text-steel">{detail}</span>
      </dd>
    </div>
  );
}
