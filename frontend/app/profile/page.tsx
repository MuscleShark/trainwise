"use client";

import { useUser } from "@clerk/nextjs";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useEffect, useState } from "react";

import { UnauthorizedError, useApi } from "../lib/api";

type Profile = {
  birthday: string | null;
  gender: string | null;
  height_cm: number | null;
  weight_kg: number | null;
  body_fat_percentage: number | null;
  fitness_goal: string | null;
  training_frequency: number | null;
  training_location: string | null;
  sleep_hours: number | null;
};

type ProfileForm = {
  birthday: string;
  gender: string;
  height_cm: string;
  weight_kg: string;
  body_fat_percentage: string;
  fitness_goal: string;
  training_frequency: string;
  training_location: string;
  sleep_hours: string;
};

const emptyForm: ProfileForm = {
  birthday: "",
  gender: "",
  height_cm: "",
  weight_kg: "",
  body_fat_percentage: "",
  fitness_goal: "",
  training_frequency: "",
  training_location: "",
  sleep_hours: "",
};

function profileToForm(profile: Profile): ProfileForm {
  return {
    birthday: profile.birthday ?? "",
    gender: profile.gender ?? "",
    height_cm: profile.height_cm?.toString() ?? "",
    weight_kg: profile.weight_kg?.toString() ?? "",
    body_fat_percentage: profile.body_fat_percentage?.toString() ?? "",
    fitness_goal: profile.fitness_goal ?? "",
    training_frequency: profile.training_frequency?.toString() ?? "",
    training_location: profile.training_location ?? "",
    sleep_hours: profile.sleep_hours?.toString() ?? "",
  };
}

function optionalNumber(value: string) {
  return value === "" ? null : Number(value);
}

export default function ProfilePage() {
  const { apiFetch, isReady } = useApi();
  const [form, setForm] = useState<ProfileForm>(emptyForm);
  const [hasProfile, setHasProfile] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");

  useEffect(() => {
    if (!isReady) return;

    async function loadProfile() {
      try {
        const response = await apiFetch("/profile");

        if (response.status === 404) {
          setHasProfile(false);
          return;
        }

        if (!response.ok) {
          throw new Error("Unable to load your profile.");
        }

        const profile: Profile = await response.json();
        setForm(profileToForm(profile));
        setHasProfile(true);
      } catch (loadError) {
        if (loadError instanceof UnauthorizedError) return;
        setError(
          loadError instanceof Error
            ? loadError.message
            : "Unable to connect to the server.",
        );
      } finally {
        setIsLoading(false);
      }
    }

    void loadProfile();
  }, [isReady, apiFetch]);

  function updateField(field: keyof ProfileForm, value: string) {
    setForm((current) => ({ ...current, [field]: value }));
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setSuccess("");

    setIsSaving(true);

    try {
      const response = await apiFetch("/profile", {
        method: hasProfile ? "PUT" : "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          birthday: form.birthday || null,
          gender: form.gender || null,
          height_cm: optionalNumber(form.height_cm),
          weight_kg: optionalNumber(form.weight_kg),
          body_fat_percentage: optionalNumber(form.body_fat_percentage),
          fitness_goal: form.fitness_goal || null,
          training_frequency: optionalNumber(form.training_frequency),
          training_location: form.training_location || null,
          sleep_hours: optionalNumber(form.sleep_hours),
        }),
      });

      const data = await response.json().catch(() => null);

      if (!response.ok) {
        const detail = data?.detail;
        const message = Array.isArray(detail)
          ? detail.map((item: { msg?: string }) => item.msg).filter(Boolean).join(" ")
          : detail;
        throw new Error(message || "Unable to save your profile.");
      }

      setForm(profileToForm(data as Profile));
      setHasProfile(true);
      setSuccess("Your profile has been saved.");
    } catch (saveError) {
      if (saveError instanceof UnauthorizedError) return;
      setError(
        saveError instanceof Error
          ? saveError.message
          : "Unable to connect to the server.",
      );
    } finally {
      setIsSaving(false);
    }
  }

  if (isLoading) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-slate-950 text-slate-400">
        Loading your profile…
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-slate-950 px-6 py-8 text-white sm:px-10">
      <header className="mx-auto flex max-w-5xl items-center justify-between border-b border-white/10 pb-6">
        <Link href="/dashboard" className="text-lg font-semibold">
          Train<span className="text-emerald-400">Wise</span>
        </Link>
        <Link
          href="/dashboard"
          className="rounded-lg border border-white/10 px-4 py-2 text-sm text-slate-300 transition hover:border-white/20 hover:text-white"
        >
          Back to dashboard
        </Link>
      </header>

      <section className="mx-auto max-w-5xl py-12">
        <p className="text-sm font-medium text-emerald-400">Profile</p>
        <h1 className="mt-2 text-4xl font-semibold tracking-tight">
          {hasProfile ? "Your fitness profile" : "Create your fitness profile"}
        </h1>
        <p className="mt-4 max-w-2xl text-slate-400">
          These details will help TrainWise personalize your progress insights
          and future recommendations.
        </p>

        <form
          onSubmit={handleSubmit}
          className="mt-10 grid gap-6 rounded-2xl border border-white/10 bg-white/[0.03] p-6 sm:grid-cols-2 sm:p-8"
        >
          <Field label="Birthday" htmlFor="birthday">
            <input
              id="birthday"
              type="date"
              value={form.birthday}
              onChange={(event) => updateField("birthday", event.target.value)}
              className="profile-input"
            />
          </Field>

          <Field label="Gender" htmlFor="gender">
            <select
              id="gender"
              value={form.gender}
              onChange={(event) => updateField("gender", event.target.value)}
              className="profile-input"
            >
              <option value="">Prefer not to say</option>
              <option value="male">Male</option>
              <option value="female">Female</option>
              <option value="non-binary">Non-binary</option>
              <option value="other">Other</option>
            </select>
          </Field>

          <Field label="Height (cm)" htmlFor="height">
            <input
              id="height"
              type="number"
              min="0"
              step="0.1"
              value={form.height_cm}
              onChange={(event) => updateField("height_cm", event.target.value)}
              className="profile-input"
              placeholder="175"
            />
          </Field>

          <Field label="Weight (kg)" htmlFor="weight">
            <input
              id="weight"
              type="number"
              min="0"
              step="0.1"
              value={form.weight_kg}
              onChange={(event) => updateField("weight_kg", event.target.value)}
              className="profile-input"
              placeholder="75"
            />
          </Field>

          <Field label="Body fat (%)" htmlFor="body-fat">
            <input
              id="body-fat"
              type="number"
              min="0"
              max="100"
              step="0.1"
              value={form.body_fat_percentage}
              onChange={(event) => updateField("body_fat_percentage", event.target.value)}
              className="profile-input"
              placeholder="18"
            />
          </Field>

          <Field label="Fitness goal" htmlFor="fitness-goal">
            <select
              id="fitness-goal"
              value={form.fitness_goal}
              onChange={(event) => updateField("fitness_goal", event.target.value)}
              className="profile-input"
            >
              <option value="">Select a goal</option>
              <option value="build muscle">Build muscle</option>
              <option value="lose fat">Lose fat</option>
              <option value="maintain">Maintain</option>
              <option value="improve performance">Improve performance</option>
            </select>
          </Field>

          <Field label="Training days per week" htmlFor="frequency">
            <input
              id="frequency"
              type="number"
              min="0"
              max="7"
              step="1"
              value={form.training_frequency}
              onChange={(event) => updateField("training_frequency", event.target.value)}
              className="profile-input"
              placeholder="4"
            />
          </Field>

          <Field label="Training location" htmlFor="location">
            <select
              id="location"
              value={form.training_location}
              onChange={(event) => updateField("training_location", event.target.value)}
              className="profile-input"
            >
              <option value="">Select a location</option>
              <option value="gym">Gym</option>
              <option value="home">Home</option>
              <option value="outdoors">Outdoors</option>
              <option value="mixed">Mixed</option>
            </select>
          </Field>

          <Field label="Average sleep (hours)" htmlFor="sleep">
            <input
              id="sleep"
              type="number"
              min="0"
              max="24"
              step="0.1"
              value={form.sleep_hours}
              onChange={(event) => updateField("sleep_hours", event.target.value)}
              className="profile-input"
              placeholder="7.5"
            />
          </Field>

          <div className="sm:col-span-2">
            {error ? (
              <p role="alert" className="mb-4 rounded-xl border border-red-400/20 bg-red-400/10 px-4 py-3 text-sm text-red-200">
                {error}
              </p>
            ) : null}
            {success ? (
              <p role="status" className="mb-4 rounded-xl border border-emerald-400/20 bg-emerald-400/10 px-4 py-3 text-sm text-emerald-200">
                {success}
              </p>
            ) : null}
            <button
              type="submit"
              disabled={isSaving}
              className="rounded-xl bg-emerald-400 px-6 py-3 font-semibold text-slate-950 transition hover:bg-emerald-300 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isSaving ? "Saving…" : hasProfile ? "Save changes" : "Create profile"}
            </button>
          </div>
        </form>

        <DeleteAccount />
      </section>
    </main>
  );
}

// Deletes the TrainWise data first, then the Clerk user. If the Clerk step fails the
// data is already gone, and signing in again starts an empty account.
function DeleteAccount() {
  const { apiFetch } = useApi();
  const { user } = useUser();
  const router = useRouter();
  const [isConfirming, setIsConfirming] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [error, setError] = useState("");

  async function deleteAccount() {
    setError("");
    setIsDeleting(true);

    try {
      const response = await apiFetch("/me", { method: "DELETE" });
      if (!response.ok) throw new Error("Unable to delete your account.");
      await user?.delete();
      router.replace("/");
    } catch (deleteError) {
      if (deleteError instanceof UnauthorizedError) return;
      setError(
        deleteError instanceof Error
          ? deleteError.message
          : "Unable to connect to the server.",
      );
      setIsDeleting(false);
    }
  }

  return (
    <div className="mt-12 rounded-2xl border border-red-400/20 p-6 sm:p-8">
      <h2 className="text-xl font-semibold">Delete account</h2>
      <p className="mt-2 max-w-2xl text-sm text-slate-400">
        Permanently deletes your account, your profile and all of your workouts.
        This cannot be undone.
      </p>
      {error ? (
        <p role="alert" className="mt-4 rounded-xl border border-red-400/20 bg-red-400/10 px-4 py-3 text-sm text-red-200">
          {error}
        </p>
      ) : null}
      {isConfirming ? (
        <div className="mt-6 flex flex-wrap gap-3">
          <button
            type="button"
            onClick={deleteAccount}
            disabled={isDeleting}
            className="rounded-xl bg-red-500 px-5 py-3 font-semibold text-white transition hover:bg-red-400 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isDeleting ? "Deleting…" : "Yes, delete everything"}
          </button>
          <button
            type="button"
            onClick={() => setIsConfirming(false)}
            disabled={isDeleting}
            className="rounded-xl border border-white/10 px-5 py-3 font-semibold text-slate-200 transition hover:border-white/20 hover:text-white"
          >
            Cancel
          </button>
        </div>
      ) : (
        <button
          type="button"
          onClick={() => setIsConfirming(true)}
          className="mt-6 rounded-xl border border-red-400/40 px-5 py-3 font-semibold text-red-300 transition hover:border-red-400 hover:text-red-200"
        >
          Delete account
        </button>
      )}
    </div>
  );
}

function Field({
  label,
  htmlFor,
  children,
}: {
  label: string;
  htmlFor: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <label htmlFor={htmlFor} className="mb-2 block text-sm font-medium text-slate-200">
        {label}
      </label>
      {children}
    </div>
  );
}
