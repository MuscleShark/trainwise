"use client";

import Link from "next/link";
import { useState } from "react";

import {
  bodyPoints,
  formatWeight,
  isFinished,
  latest,
  rangeStart,
  toUnit,
  volumeKg,
  WEEKLY_AFTER_DAYS,
  weeklyVolume,
  weekStreak,
  workingSets,
  workoutsThisWeek,
  type Range,
} from "../lib/training";
import { BarChart, LineChart } from "./charts";
import { useReview } from "./data";
import { axisDate, fullDay, percent, shortDay, weekRange, wholeNumber } from "./format";

const RANGES: Range[] = ["week", "month", "year", "all"];

export default function OverviewPage() {
  const { training, t, locale, weekStartsOn } = useReview();
  const [now] = useState(() => new Date());
  if (!training) return null;

  const finished = training.workouts.filter(isFinished);
  const thisWeek = workoutsThisWeek(finished, now, weekStartsOn);
  const planned = training.plannedDaysPerWeek;

  return (
    <>
      <h1 className="type-stamp text-4xl sm:text-5xl">{t.yourTraining}</h1>

      {finished.length === 0 ? (
        <p className="mt-6 max-w-xl leading-relaxed text-steel">{t.noWorkouts}</p>
      ) : (
        <>
          <dl className="mt-8 grid grid-cols-3 divide-x divide-ink/15 border-y border-ink/15">
            <Stat label={t.workouts} value={wholeNumber(finished.length, locale)} />
            <Stat
              label={t.thisWeek}
              value={planned ? `${thisWeek}/${planned}` : wholeNumber(thisWeek, locale)}
            />
            <Stat label={t.weeksInARow} value={wholeNumber(weekStreak(finished, now, weekStartsOn), locale)} />
          </dl>

          <section className="mt-12">
            <h2 className="text-xl font-semibold">{t.weeklyVolume}</h2>
            <p className="mt-1 max-w-2xl text-sm text-steel">{t.weeklyVolumeNote(training.unit)}</p>
            <div className="mt-5 rounded-sm bg-card p-4 sm:p-5">
              <BarChart
                title={t.weeklyVolume}
                labelHeading={t.week}
                formatValue={(value) => wholeNumber(value, locale)}
                bars={weeklyVolume(finished, training.loadTypes, 12, now, weekStartsOn).map((week) => ({
                  axisLabel: shortDay(week.start, locale),
                  label: weekRange(week.start, locale),
                  value: toUnit(week.kilograms, training.unit),
                }))}
              />
            </div>
          </section>
        </>
      )}

      <BodySection now={now} />

      {finished.length > 0 ? <RecentWorkouts /> : null}
    </>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col justify-between px-3 py-5 first:pl-0 sm:px-6">
      <dt className="text-sm text-steel">{label}</dt>
      <dd className="type-stamp mt-1 text-4xl tabular-nums sm:text-6xl">{value}</dd>
    </div>
  );
}

function BodySection({ now }: { now: Date }) {
  const { training, t, locale, weekStartsOn } = useReview();
  const [range, setRange] = useState<Range>("month");
  if (!training) return null;
  const unit = training.unit;

  return (
    <section className="mt-14">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <h2 className="text-xl font-semibold">{t.body}</h2>
        <div role="radiogroup" aria-label={t.period} className="flex rounded-sm border border-ink/15 p-0.5 text-sm">
          {RANGES.map((option) => (
            <button
              key={option}
              type="button"
              role="radio"
              aria-checked={range === option}
              onClick={() => setRange(option)}
              className={`rounded-[3px] px-3.5 py-1.5 font-medium transition-colors ${
                range === option ? "bg-ink text-chalk" : "text-steel hover:text-ink"
              }`}
            >
              {t.ranges[option]}
            </button>
          ))}
        </div>
      </div>
      <div className="mt-5 grid gap-5 lg:grid-cols-2">
        <BodyCard
          title={t.bodyWeight}
          kind="weight"
          empty={t.noBodyWeight}
          range={range}
          now={now}
          unitLabel={unit}
          display={(kg) => toUnit(kg, unit)}
          format={(value) => value.toLocaleString(locale, { maximumFractionDigits: 1 })}
          formatLatest={(kg) => `${formatWeight(kg, unit, locale)} ${unit}`}
          weekStartsOn={weekStartsOn}
        />
        <BodyCard
          title={t.bodyFat}
          kind="body_fat"
          empty={t.noBodyFat}
          range={range}
          now={now}
          unitLabel="%"
          display={(value) => value}
          format={(value) => value.toLocaleString(locale, { maximumFractionDigits: 1 })}
          formatLatest={(value) => percent(value, locale)}
          weekStartsOn={weekStartsOn}
        />
      </div>
    </section>
  );
}

function BodyCard({
  title,
  kind,
  empty,
  range,
  now,
  unitLabel,
  display,
  format,
  formatLatest,
  weekStartsOn,
}: {
  title: string;
  kind: string;
  empty: string;
  range: Range;
  now: Date;
  unitLabel: string;
  display: (stored: number) => number;
  format: (value: number) => string;
  formatLatest: (stored: number) => string;
  weekStartsOn: number;
}) {
  const { training, t, locale } = useReview();
  const measurements = training?.measurements ?? [];
  const newest = latest(measurements, kind);
  const points = bodyPoints(measurements, kind, range, now, weekStartsOn).map((point) => ({
    date: point.date,
    value: display(point.value),
  }));
  const start = rangeStart(range, now) ?? points[0]?.date ?? now;
  const end = range === "all" ? (points[points.length - 1]?.date ?? now) : now;
  const weekly =
    points.length > 1 &&
    points[points.length - 1].date.getTime() - points[0].date.getTime() > WEEKLY_AFTER_DAYS * 86_400_000;

  return (
    <div className="rounded-sm bg-card p-4 sm:p-5">
      <h3 className="text-sm text-steel">{title}</h3>
      {newest ? (
        <>
          <p className="mt-1 flex items-baseline justify-between gap-3">
            <span className="type-stamp text-3xl tabular-nums">{formatLatest(newest.value)}</span>
            <span className="text-sm text-steel">{shortDay(new Date(newest.measured_at), locale)}</span>
          </p>
          <div className="mt-4">
            {points.length ? (
              <LineChart
                points={points}
                start={start}
                end={end}
                title={`${title} (${unitLabel})`}
                dateHeading={t.date}
                formatValue={format}
                formatAxisDate={(date) => axisDate(date, range, locale)}
                formatDate={(date) => fullDay(date, locale)}
              />
            ) : (
              <p className="py-8 text-sm text-steel">{t.nothingInRange}</p>
            )}
            {weekly ? <p className="mt-2 text-xs text-steel">{t.weeklyAverages}</p> : null}
          </div>
        </>
      ) : (
        <p className="mt-2 text-sm leading-relaxed text-steel">{empty}</p>
      )}
    </div>
  );
}

function RecentWorkouts() {
  const { training, t, locale } = useReview();
  if (!training) return null;
  const recent = training.workouts.filter(isFinished).slice(0, 5);

  return (
    <section className="mt-14">
      <div className="flex items-baseline justify-between gap-4">
        <h2 className="text-xl font-semibold">{t.recentWorkouts}</h2>
        <Link href="/review/history" className="text-sm font-medium text-accent hover:underline">
          {t.allWorkouts}
        </Link>
      </div>
      <ul className="mt-4 divide-y divide-ink/15 border-y border-ink/15">
        {recent.map((workout) => {
          const sets = workout.exercises.reduce((sum, item) => sum + workingSets(item.sets).length, 0);
          return (
            <li key={workout.id} className="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1 py-3">
              <span className="font-medium">{workout.title}</span>
              <span className="text-sm text-steel tabular-nums">
                {fullDay(new Date(workout.started_at), locale)} · {t.sets(sets)} ·{" "}
                {formatWeight(volumeKg(workout, training.loadTypes), training.unit, locale)} {training.unit}
              </span>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
