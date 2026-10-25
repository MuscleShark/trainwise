import Link from "next/link";

import Logo from "./components/Logo";

const features = [
  {
    title: "Log a set in two taps",
    body: "Every set starts with last time's weight and reps. Finish it and the rest timer starts, even with the phone locked. Works without signal.",
  },
  {
    title: "See every lift move",
    body: "Estimated one-rep max, personal records and weekly sets per muscle, for each machine and bar you use.",
  },
  {
    title: "A coach that shows its work",
    body: "Suggestions follow published training research and your own history, and each one says which numbers it used.",
  },
];

export default function Home() {
  return (
    <div className="flex flex-1 flex-col">
      <header className="mx-auto flex w-full max-w-6xl items-center justify-between px-4 py-6 sm:px-8">
        <Link href="/" aria-label="IronSage home">
          <Logo height={52} />
        </Link>
        <Link
          href="/login"
          className="rounded-md px-3 py-2 text-sm font-medium text-steel transition-colors hover:text-ink"
        >
          Sign in
        </Link>
      </header>

      <main className="mx-auto w-full max-w-6xl flex-1 px-4 sm:px-8">
        <section className="grid items-center gap-12 py-12 sm:py-20 lg:grid-cols-[1.1fr_1fr]">
          <div>
            <h1 className="type-stamp text-5xl leading-[0.95] sm:text-7xl">
              Know what to lift next.
            </h1>
            <p className="mt-8 max-w-xl text-lg leading-relaxed text-steel">
              IronSage logs your sets, reads sleep and heart rate from Apple Health,
              and suggests the weight and reps for your next session, with the reason
              behind every change.
            </p>
            <p className="mt-8 text-sm font-medium text-ink">Coming soon to iPhone.</p>
          </div>

          <LogbookEntry />
        </section>

        <section
          aria-label="Features"
          className="grid gap-10 border-t border-ink/15 py-14 sm:grid-cols-3"
        >
          {features.map((feature) => (
            <div key={feature.title}>
              <h2 className="text-lg font-semibold">{feature.title}</h2>
              <p className="mt-3 leading-relaxed text-steel">{feature.body}</p>
            </div>
          ))}
        </section>
      </main>

      <footer className="mx-auto flex w-full max-w-6xl flex-wrap gap-x-6 gap-y-2 px-4 py-8 text-sm text-steel sm:px-8">
        <span>© {new Date().getFullYear()} IronSage</span>
        <Link href="/privacy" className="hover:text-ink">
          Privacy
        </Link>
        <Link href="/support" className="hover:text-ink">
          Support
        </Link>
      </footer>
    </div>
  );
}

// The product's core moment, set like a page in a training log.
function LogbookEntry() {
  const lastSets = ["60 × 8", "60 × 8", "60 × 7"];

  return (
    <figure
      aria-label="Example coach suggestion for bench press"
      className="rounded-sm border border-ink/15 bg-card p-6 shadow-[6px_6px_0_var(--chalk-deep)] sm:p-8"
    >
      <div className="flex items-baseline justify-between gap-4">
        <h2 className="type-stamp text-2xl">Bench press</h2>
        <span className="text-sm text-steel">Barbell, kg</span>
      </div>

      <dl className="mt-6 grid grid-cols-[5rem_1fr] gap-y-3 tabular-nums">
        <dt className="text-sm text-steel">Last time</dt>
        <dd className="flex flex-wrap gap-x-4 gap-y-1">
          {lastSets.map((set, index) => (
            <span key={index}>{set}</span>
          ))}
        </dd>
        <dt className="text-sm text-steel">Today</dt>
        <dd>
          <span className="font-semibold">60 × 8, three sets.</span>{" "}
          <span className="font-semibold text-accent">Hold the weight.</span>
        </dd>
      </dl>

      <figcaption className="mt-6 border-l-4 border-accent pl-4 leading-relaxed">
        You slept 5 h 40 min and your HRV is 18% below your usual. The last set
        also fell one rep short, so stay at 60 kg and aim for 8 on every set.
      </figcaption>
    </figure>
  );
}
