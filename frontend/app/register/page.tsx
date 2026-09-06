"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";

export default function RegisterPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [error, setError] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");

    if (password !== confirmPassword) {
      setError("Passwords do not match.");
      return;
    }

    setIsSubmitting(true);

    try {
      const response = await fetch(`${API_URL}/users`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          email: email.trim(),
          password,
        }),
      });

      const data = await response.json().catch(() => null);

      if (!response.ok) {
        const detail = data?.detail;
        const message = Array.isArray(detail)
          ? detail.map((item: { msg?: string }) => item.msg).filter(Boolean).join(" ")
          : detail;

        throw new Error(message || "Unable to create your account.");
      }

      router.push("/login");
    } catch (registerError) {
      setError(
        registerError instanceof Error
          ? registerError.message
          : "Unable to connect to the server.",
      );
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <main className="grid min-h-screen bg-slate-950 text-white lg:grid-cols-2">
      <section className="hidden border-r border-white/10 p-12 lg:flex lg:flex-col lg:justify-between">
        <Link href="/" className="text-lg font-semibold tracking-tight">
          Train<span className="text-emerald-400">Wise</span>
        </Link>
        <div className="max-w-lg">
          <p className="mb-5 text-sm font-semibold uppercase tracking-[0.3em] text-emerald-400">
            Start building momentum
          </p>
          <h1 className="text-5xl font-semibold leading-tight tracking-tight">
            Your strongest routine starts here.
          </h1>
          <p className="mt-6 text-lg leading-8 text-slate-300">
            Create an account to track workouts, understand recovery, and see
            your progress clearly.
          </p>
        </div>
        <p className="text-sm text-slate-500">One session at a time.</p>
      </section>

      <section className="flex items-center justify-center px-6 py-12 sm:px-12">
        <div className="w-full max-w-md">
          <Link href="/" className="mb-12 block text-lg font-semibold lg:hidden">
            Train<span className="text-emerald-400">Wise</span>
          </Link>
          <p className="text-sm font-medium text-emerald-400">Get started</p>
          <h2 className="mt-2 text-3xl font-semibold tracking-tight">
            Create your account
          </h2>
          <p className="mt-3 text-slate-400">
            Already registered?{" "}
            <Link href="/login" className="font-medium text-emerald-400 hover:text-emerald-300">
              Sign in
            </Link>
          </p>

          <form className="mt-8 space-y-5" onSubmit={handleSubmit}>
            <div>
              <label htmlFor="email" className="mb-2 block text-sm font-medium">
                Email
              </label>
              <input
                id="email"
                name="email"
                type="email"
                autoComplete="email"
                required
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                placeholder="you@example.com"
                className="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-white outline-none transition placeholder:text-slate-600 focus:border-emerald-400 focus:ring-2 focus:ring-emerald-400/20"
              />
            </div>

            <div>
              <label htmlFor="password" className="mb-2 block text-sm font-medium">
                Password
              </label>
              <input
                id="password"
                name="password"
                type="password"
                autoComplete="new-password"
                required
                minLength={8}
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                placeholder="At least 8 characters"
                className="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-white outline-none transition placeholder:text-slate-600 focus:border-emerald-400 focus:ring-2 focus:ring-emerald-400/20"
              />
            </div>

            <div>
              <label htmlFor="confirm-password" className="mb-2 block text-sm font-medium">
                Confirm password
              </label>
              <input
                id="confirm-password"
                name="confirmPassword"
                type="password"
                autoComplete="new-password"
                required
                minLength={8}
                value={confirmPassword}
                onChange={(event) => setConfirmPassword(event.target.value)}
                placeholder="Enter your password again"
                className="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-white outline-none transition placeholder:text-slate-600 focus:border-emerald-400 focus:ring-2 focus:ring-emerald-400/20"
              />
            </div>

            {error ? (
              <p
                role="alert"
                className="rounded-xl border border-red-400/20 bg-red-400/10 px-4 py-3 text-sm text-red-200"
              >
                {error}
              </p>
            ) : null}

            <button
              type="submit"
              disabled={isSubmitting}
              className="w-full rounded-xl bg-emerald-400 px-4 py-3 font-semibold text-slate-950 transition hover:bg-emerald-300 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isSubmitting ? "Creating account…" : "Create account"}
            </button>
          </form>
        </div>
      </section>
    </main>
  );
}
