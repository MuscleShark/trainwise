import Link from "next/link";

export default function Home() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-950 px-6 text-white">
      <section className="max-w-2xl text-center">
        <p className="mb-4 text-sm font-semibold uppercase tracking-[0.35em] text-emerald-400">
          TrainWise
        </p>
        <h1 className="text-5xl font-semibold tracking-tight sm:text-6xl">
          Train with better data.
        </h1>
        <p className="mx-auto mt-6 max-w-xl text-lg leading-8 text-slate-300">
          Keep your training, recovery, and progress in one place—and turn it
          into decisions you can act on.
        </p>
        <Link
          href="/login"
          className="mt-10 inline-flex rounded-xl bg-emerald-400 px-6 py-3 font-semibold text-slate-950 transition hover:bg-emerald-300 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-emerald-400"
        >
          Sign in to TrainWise
        </Link>
      </section>
    </main>
  );
}
