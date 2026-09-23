"use client";

import Link from "next/link";
import { FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";

type Workout = {
  id: number;
  workout_date: string;
  workout_type: string;
  duration_minutes: number;
  notes: string | null;
};

type WorkoutForm = {
  workout_date: string;
  workout_type: string;
  duration_minutes: string;
  notes: string;
};

const emptyForm: WorkoutForm = {
  workout_date: "",
  workout_type: "",
  duration_minutes: "",
  notes: "",
};

export default function WorkoutsPage() {
  const router = useRouter();
  const [workouts, setWorkouts] = useState<Workout[]>([]);
  const [form, setForm] = useState<WorkoutForm>(emptyForm);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [deletingId, setDeletingId] = useState<number | null>(null);
  const [error, setError] = useState("");

  function handleUnauthorized() {
    localStorage.removeItem("access_token");
    router.replace("/login");
  }

  useEffect(() => {
    const token = localStorage.getItem("access_token");
    if (!token) {
      router.replace("/login");
      return;
    }

    async function loadWorkouts() {
      try {
        const response = await fetch(`${API_URL}/workouts`, {
          headers: { Authorization: `Bearer ${token}` },
        });

        if (response.status === 401) {
          localStorage.removeItem("access_token");
          router.replace("/login");
          return;
        }
        if (!response.ok) throw new Error("Unable to load your workouts.");

        const data: Workout[] = await response.json();
        setWorkouts(data);
      } catch (loadError) {
        setError(
          loadError instanceof Error
            ? loadError.message
            : "Unable to connect to the server.",
        );
      } finally {
        setIsLoading(false);
      }
    }

    void loadWorkouts();
  }, [router]);

  function updateField(field: keyof WorkoutForm, value: string) {
    setForm((current) => ({ ...current, [field]: value }));
  }

  function startEditing(workout: Workout) {
    setEditingId(workout.id);
    setForm({
      workout_date: workout.workout_date,
      workout_type: workout.workout_type,
      duration_minutes: workout.duration_minutes.toString(),
      notes: workout.notes ?? "",
    });
    setError("");
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function resetForm() {
    setEditingId(null);
    setForm(emptyForm);
    setError("");
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");

    const token = localStorage.getItem("access_token");
    if (!token) {
      handleUnauthorized();
      return;
    }

    setIsSaving(true);
    try {
      const url = editingId
        ? `${API_URL}/workouts/${editingId}`
        : `${API_URL}/workouts`;
      const response = await fetch(url, {
        method: editingId ? "PUT" : "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          workout_date: form.workout_date,
          workout_type: form.workout_type.trim(),
          duration_minutes: Number(form.duration_minutes),
          notes: form.notes.trim() || null,
        }),
      });

      if (response.status === 401) {
        handleUnauthorized();
        return;
      }

      const data = await response.json().catch(() => null);
      if (!response.ok) {
        const detail = data?.detail;
        const message = Array.isArray(detail)
          ? detail.map((item: { msg?: string }) => item.msg).filter(Boolean).join(" ")
          : detail;
        throw new Error(message || "Unable to save the workout.");
      }

      const savedWorkout = data as Workout;
      setWorkouts((current) =>
        editingId
          ? current.map((workout) =>
              workout.id === editingId ? savedWorkout : workout,
            )
          : [savedWorkout, ...current],
      );
      resetForm();
    } catch (saveError) {
      setError(
        saveError instanceof Error
          ? saveError.message
          : "Unable to connect to the server.",
      );
    } finally {
      setIsSaving(false);
    }
  }

  async function deleteWorkout(workoutId: number) {
    if (!window.confirm("Delete this workout? This action cannot be undone.")) {
      return;
    }

    const token = localStorage.getItem("access_token");
    if (!token) {
      handleUnauthorized();
      return;
    }

    setDeletingId(workoutId);
    setError("");
    try {
      const response = await fetch(`${API_URL}/workouts/${workoutId}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` },
      });

      if (response.status === 401) {
        handleUnauthorized();
        return;
      }
      if (!response.ok) throw new Error("Unable to delete the workout.");

      setWorkouts((current) =>
        current.filter((workout) => workout.id !== workoutId),
      );
      if (editingId === workoutId) resetForm();
    } catch (deleteError) {
      setError(
        deleteError instanceof Error
          ? deleteError.message
          : "Unable to connect to the server.",
      );
    } finally {
      setDeletingId(null);
    }
  }

  if (isLoading) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-slate-950 text-slate-400">
        Loading your workouts…
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-slate-950 px-6 py-8 text-white sm:px-10">
      <header className="mx-auto flex max-w-6xl items-center justify-between border-b border-white/10 pb-6">
        <Link href="/dashboard" className="text-lg font-semibold">
          Train<span className="text-emerald-400">Wise</span>
        </Link>
        <Link href="/dashboard" className="rounded-lg border border-white/10 px-4 py-2 text-sm text-slate-300 hover:text-white">
          Back to dashboard
        </Link>
      </header>

      <section className="mx-auto grid max-w-6xl gap-10 py-12 lg:grid-cols-[380px_1fr]">
        <div>
          <p className="text-sm font-medium text-emerald-400">Workout log</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight">
            {editingId ? "Edit workout" : "Record a workout"}
          </h1>

          <form onSubmit={handleSubmit} className="mt-8 space-y-5 rounded-2xl border border-white/10 bg-white/[0.03] p-6">
            <WorkoutField label="Date" htmlFor="workout-date">
              <input id="workout-date" type="date" required value={form.workout_date} onChange={(event) => updateField("workout_date", event.target.value)} className="workout-input" />
            </WorkoutField>
            <WorkoutField label="Workout type" htmlFor="workout-type">
              <input id="workout-type" type="text" required maxLength={50} value={form.workout_type} onChange={(event) => updateField("workout_type", event.target.value)} className="workout-input" placeholder="Strength, cardio, mobility…" />
            </WorkoutField>
            <WorkoutField label="Duration (minutes)" htmlFor="duration">
              <input id="duration" type="number" required min="1" value={form.duration_minutes} onChange={(event) => updateField("duration_minutes", event.target.value)} className="workout-input" placeholder="60" />
            </WorkoutField>
            <WorkoutField label="Notes" htmlFor="notes">
              <textarea id="notes" rows={4} value={form.notes} onChange={(event) => updateField("notes", event.target.value)} className="workout-input resize-none" placeholder="Exercises, intensity, how you felt…" />
            </WorkoutField>

            {error ? <p role="alert" className="rounded-xl border border-red-400/20 bg-red-400/10 px-4 py-3 text-sm text-red-200">{error}</p> : null}

            <div className="flex gap-3">
              <button type="submit" disabled={isSaving} className="rounded-xl bg-emerald-400 px-5 py-3 font-semibold text-slate-950 hover:bg-emerald-300 disabled:opacity-60">
                {isSaving ? "Saving…" : editingId ? "Save changes" : "Add workout"}
              </button>
              {editingId ? <button type="button" onClick={resetForm} className="rounded-xl border border-white/10 px-5 py-3 text-slate-300 hover:text-white">Cancel</button> : null}
            </div>
          </form>
        </div>

        <div>
          <div className="flex items-end justify-between">
            <div>
              <p className="text-sm font-medium text-emerald-400">History</p>
              <h2 className="mt-2 text-3xl font-semibold tracking-tight">Your workouts</h2>
            </div>
            <p className="text-sm text-slate-500">{workouts.length} total</p>
          </div>

          {workouts.length === 0 ? (
            <div className="mt-8 rounded-2xl border border-dashed border-white/15 p-10 text-center text-slate-400">
              No workouts yet. Record your first session.
            </div>
          ) : (
            <div className="mt-8 space-y-4">
              {workouts.map((workout) => (
                <article key={workout.id} className="rounded-2xl border border-white/10 bg-white/[0.03] p-6">
                  <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-start">
                    <div>
                      <p className="text-sm text-emerald-400">{workout.workout_date}</p>
                      <h3 className="mt-1 text-xl font-semibold">{workout.workout_type}</h3>
                      <p className="mt-2 text-sm text-slate-400">{workout.duration_minutes} minutes</p>
                      {workout.notes ? <p className="mt-4 whitespace-pre-wrap text-slate-300">{workout.notes}</p> : null}
                    </div>
                    <div className="flex gap-2">
                      <button type="button" onClick={() => startEditing(workout)} className="rounded-lg border border-white/10 px-3 py-2 text-sm text-slate-300 hover:text-white">Edit</button>
                      <button type="button" disabled={deletingId === workout.id} onClick={() => void deleteWorkout(workout.id)} className="rounded-lg border border-red-400/20 px-3 py-2 text-sm text-red-300 hover:bg-red-400/10 disabled:opacity-50">
                        {deletingId === workout.id ? "Deleting…" : "Delete"}
                      </button>
                    </div>
                  </div>
                </article>
              ))}
            </div>
          )}
        </div>
      </section>
    </main>
  );
}

function WorkoutField({ label, htmlFor, children }: { label: string; htmlFor: string; children: React.ReactNode }) {
  return (
    <div>
      <label htmlFor={htmlFor} className="mb-2 block text-sm font-medium text-slate-200">{label}</label>
      {children}
    </div>
  );
}
