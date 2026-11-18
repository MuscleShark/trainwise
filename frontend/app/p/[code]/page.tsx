import type { Metadata } from "next";
import { headers } from "next/headers";
import Link from "next/link";
import { notFound } from "next/navigation";

import type { components } from "../../lib/api-types";
import Logo from "../../components/Logo";

type SharedTemplate = components["schemas"]["SharedTemplate"];
type SharedExercise = components["schemas"]["SharedExercise"];
type TemplateSet = components["schemas"]["TemplateSetRead"];

// Read here, not from lib/api.ts: that module is for the browser.
const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";

type Lang = "en" | "zh";

const WORDS = {
  en: {
    sharedPlan: "A shared training plan",
    day: (n: number) => (n === 1 ? "1 day" : `${n} days`),
    perWeek: (n: number) => `${n} a week`,
    rest: "Rest",
    sets: (n: number) => (n === 1 ? "1 set" : `${n} sets`),
    minutes: (n: number) => `${n} min`,
    open: "Open in IronSage",
    openHint:
      "On your iPhone with IronSage, the button opens the plan in the app, where Copy to my templates makes it yours to use and change.",
    noApp: "IronSage is a strength-training log for iPhone. It's coming to the App Store soon.",
    gone: "This plan isn't shared anymore.",
  },
  zh: {
    sharedPlan: "分享的训练计划",
    day: (n: number) => `${n} 天`,
    perWeek: (n: number) => `每周 ${n} 次`,
    rest: "休息",
    sets: (n: number) => `${n} 组`,
    minutes: (n: number) => `${n} 分钟`,
    open: "在 IronSage 中打开",
    openHint: "在装了 IronSage 的 iPhone 上，点按钮会在 App 里打开这个计划，点“复制到我的模板”就能直接用，也可以修改。",
    noApp: "IronSage 是一款 iPhone 力量训练记录 App，即将上架 App Store。",
    gone: "这个计划已经不再分享了。",
  },
} as const;

async function language(): Promise<Lang> {
  const accepted = (await headers()).get("accept-language") ?? "";
  return accepted.trim().toLowerCase().startsWith("zh") ? "zh" : "en";
}

async function load(code: string): Promise<SharedTemplate | null> {
  if (!/^[A-Za-z0-9]{1,16}$/.test(code)) return null;
  const response = await fetch(`${API_URL}/v1/shared-templates/${code}`, {
    // The owner can share again (a new snapshot) or stop: a minute old at most.
    next: { revalidate: 60 },
  });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`The shared plan didn't load (${response.status}).`);
  return response.json();
}

function planName(plan: SharedTemplate, lang: Lang) {
  return (lang === "zh" && plan.name_zh) || plan.name_en;
}

function exerciseName(exercise: SharedExercise | undefined, lang: Lang) {
  if (!exercise) return "";
  return (lang === "zh" && exercise.name_zh) || exercise.name_en;
}

function clock(seconds: number) {
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

/** "3 × 6–10", or "15 min" for cardio, from the sets planned. */
function setsText(sets: TemplateSet[], lang: Lang) {
  const words = WORDS[lang];
  const minutes = sets.reduce((total, set) => total + (set.duration_seconds ?? 0), 0);
  if (minutes > 0) return words.minutes(Math.round(minutes / 60));
  if (sets.length === 0) return "";
  const first = sets.find((set) => set.set_type !== "warmup") ?? sets[0];
  const { rep_min: low, rep_max: high } = first;
  const reps = low && high && low !== high ? `${low}–${high}` : (low ?? high);
  return reps ? `${sets.length} × ${reps}` : words.sets(sets.length);
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ code: string }>;
}): Promise<Metadata> {
  const { code } = await params;
  const [plan, lang] = await Promise.all([load(code), language()]);
  if (!plan) return { title: "IronSage" };
  const words = WORDS[lang];
  const description = [words.sharedPlan, words.day(plan.days.length)].join(" · ");
  return {
    title: `${planName(plan, lang)} | IronSage`,
    description,
    openGraph: { title: planName(plan, lang), description, siteName: "IronSage" },
    // A shared link is for the people it was sent to, not for search engines.
    robots: { index: false, follow: false },
  };
}

/** A template someone shared (ironsage.app/p/<code>): what it holds, and a button that
 * opens it in the app to copy. The same link opens the app directly on an iPhone that
 * has it (apple-app-site-association). */
export default async function SharedTemplatePage({
  params,
}: {
  params: Promise<{ code: string }>;
}) {
  const { code } = await params;
  const [plan, lang] = await Promise.all([load(code), language()]);
  if (!plan) notFound();
  const words = WORDS[lang];
  const exercises = new Map(plan.exercises.map((exercise) => [exercise.id, exercise]));

  return (
    <div lang={lang === "zh" ? "zh-Hans" : "en"} className="flex flex-1 flex-col">
      <header className="mx-auto flex w-full max-w-3xl items-center px-4 py-6 sm:px-8">
        <Link href="/" aria-label="IronSage home">
          <Logo height={52} />
        </Link>
      </header>

      <main className="mx-auto w-full max-w-3xl flex-1 px-4 pb-16 pt-2 sm:px-8">
        <p className="text-sm font-medium text-steel">{words.sharedPlan}</p>
        <h1 className="type-stamp mt-2 text-4xl break-words">{planName(plan, lang)}</h1>
        <p className="mt-3 text-steel">
          {[
            words.day(plan.days.length),
            plan.days_per_week ? words.perWeek(plan.days_per_week) : null,
          ]
            .filter(Boolean)
            .join(" · ")}
        </p>
        {plan.notes ? <p className="mt-4 whitespace-pre-line leading-relaxed">{plan.notes}</p> : null}

        <div className="mt-8 flex flex-col gap-3 sm:flex-row sm:items-center">
          <a
            href={`ironsage://shared/${code}`}
            className="inline-flex justify-center rounded-full bg-accent px-6 py-3 font-semibold text-white transition-opacity hover:opacity-90"
          >
            {words.open}
          </a>
        </div>
        <p className="mt-3 max-w-prose text-sm leading-relaxed text-steel">{words.openHint}</p>

        <div className="mt-10 space-y-6">
          {plan.days.map((day) => (
            <section key={day.id} className="rounded-2xl bg-card p-5">
              <h2 className="text-lg font-semibold">{(lang === "zh" && day.name_zh) || day.name}</h2>
              <ul className="mt-3 divide-y divide-chalk-deep">
                {day.exercises.map((item) => (
                  <li key={item.id} className="flex items-baseline justify-between gap-4 py-2.5">
                    <span>{exerciseName(exercises.get(item.exercise_id), lang)}</span>
                    <span className="shrink-0 text-right tabular-nums text-steel">
                      {[
                        setsText(item.sets, lang),
                        item.rest_seconds ? `${words.rest} ${clock(item.rest_seconds)}` : null,
                      ]
                        .filter(Boolean)
                        .join(" · ")}
                    </span>
                  </li>
                ))}
              </ul>
            </section>
          ))}
        </div>

        <p className="mt-10 text-sm text-steel">{words.noApp}</p>
      </main>
    </div>
  );
}
