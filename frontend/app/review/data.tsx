"use client";

import { createContext, useContext, useEffect, useMemo, useState } from "react";

import { UnauthorizedError, useApi } from "../lib/api";
import type { components } from "../lib/api-types";
import type { LoadType, WeightUnit } from "../lib/training";
import { localeFor, strings, useLanguage, weekStartFor, type Language, type Strings } from "./strings";

type Workout = components["schemas"]["WorkoutRead"];
type Exercise = components["schemas"]["ExerciseRead"];
type Measurement = components["schemas"]["BodyMeasurementRead"];
type Profile = components["schemas"]["ProfileRead"];
type WorkoutPage = components["schemas"]["WorkoutPage"];

export interface Training {
  workouts: Workout[];
  exercises: Map<string, Exercise>;
  loadTypes: Map<string, LoadType>;
  measurements: Measurement[];
  unit: WeightUnit;
  plannedDaysPerWeek: number | null;
}

interface ReviewContext {
  training: Training | null;
  error: boolean;
  language: Language;
  locale: string;
  weekStartsOn: number;
  t: Strings;
  exerciseName: (id: string) => string;
}

const Context = createContext<ReviewContext | null>(null);

/** Everything the review pages show, read once from the API (read-only). */
export function TrainingProvider({ children }: { children: React.ReactNode }) {
  const { apiFetch, isReady } = useApi();
  const language = useLanguage();
  const [training, setTraining] = useState<Training | null>(null);
  const [error, setError] = useState(false);

  useEffect(() => {
    if (!isReady) return;

    async function json<T>(path: string): Promise<T> {
      const response = await apiFetch(path);
      if (!response.ok) throw new Error(`${path}: ${response.status}`);
      return response.json();
    }

    async function load() {
      try {
        const profileResponse = await apiFetch("/profile");
        // No profile until the app's first-run setup.
        const profile: Profile | null = profileResponse.ok ? await profileResponse.json() : null;
        const [exercises, measurements] = await Promise.all([
          json<Exercise[]>("/exercises"),
          json<Measurement[]>("/body-measurements"),
        ]);
        const workouts: Workout[] = [];
        let before: string | null | undefined;
        do {
          const query = before ? `&before=${encodeURIComponent(before)}` : "";
          const page = await json<WorkoutPage>(`/workouts?limit=100${query}`);
          workouts.push(...page.items);
          before = page.next_before;
        } while (before);

        setTraining({
          workouts,
          exercises: new Map(exercises.map((exercise) => [exercise.id, exercise])),
          loadTypes: new Map(exercises.map((exercise) => [exercise.id, exercise.load_type])),
          measurements,
          unit: profile
            ? profile.unit_system === "imperial"
              ? "lb"
              : "kg"
            : navigator.language === "en-US"
              ? "lb"
              : "kg",
          plannedDaysPerWeek: profile?.training_days_per_week ?? null,
        });
      } catch (loadError) {
        if (loadError instanceof UnauthorizedError) return;
        setError(true);
      }
    }

    void load();
  }, [isReady, apiFetch]);

  const value = useMemo<ReviewContext>(() => {
    const locale = localeFor(language);
    return {
      training,
      error,
      language,
      locale,
      weekStartsOn: weekStartFor(locale),
      t: strings(language),
      exerciseName: (id) => {
        const exercise = training?.exercises.get(id);
        if (!exercise) return "–";
        return language === "zh" ? (exercise.name_zh ?? exercise.name_en) : exercise.name_en;
      },
    };
  }, [training, error, language]);

  return <Context.Provider value={value}>{children}</Context.Provider>;
}

export function useReview(): ReviewContext {
  const context = useContext(Context);
  if (!context) throw new Error("useReview needs TrainingProvider");
  return context;
}
