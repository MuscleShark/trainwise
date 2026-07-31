"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";

type User = {
  id: number;
  email: string;
};

export default function DashboardPage() {
  const router = useRouter();
  const [user, setUser] = useState<User | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    const token = localStorage.getItem("access_token");

    if (!token) {
      router.replace("/login");
      return;
    }

    async function loadUser() {
      try {
        const response = await fetch(`${API_URL}/me`, {
          headers: { Authorization: `Bearer ${token}` },
        });

        if (!response.ok) {
          localStorage.removeItem("access_token");
          router.replace("/login");
          return;
        }

        setUser(await response.json());
      } catch {
        setError("Could not connect to the TrainWise API.");
      }
    }

    void loadUser();
  }, [router]);

  function signOut() {
    localStorage.removeItem("access_token");
    router.replace("/login");
  }

  return (
    <main className="min-h-screen bg-slate-950 px-6 py-8 text-white sm:px-10">
      <header className="mx-auto flex max-w-6xl items-center justify-between border-b border-white/10 pb-6">
        <p className="text-lg font-semibold">
          Train<span className="text-emerald-400">Wise</span>
        </p>
        <button
          type="button"
          onClick={signOut}
          className="rounded-lg border border-white/10 px-4 py-2 text-sm text-slate-300 transition hover:border-white/20 hover:text-white"
        >
          Sign out
        </button>
      </header>

      <section className="mx-auto max-w-6xl py-16">
        {error ? (
          <p className="rounded-xl border border-red-400/20 bg-red-400/10 p-4 text-red-200">
            {error}
          </p>
        ) : user ? (
          <>
            <p className="text-sm font-medium text-emerald-400">Dashboard</p>
            <h1 className="mt-2 text-4xl font-semibold tracking-tight">
              Welcome back, {user.email}
            </h1>
            <p className="mt-4 text-slate-400">
              Your login flow is connected. Profile and workout data come next.
            </p>
          </>
        ) : (
          <p className="text-slate-400">Loading your dashboard…</p>
        )}
      </section>
    </main>
  );
}
