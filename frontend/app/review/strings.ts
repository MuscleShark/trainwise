"use client";

import { useSyncExternalStore } from "react";

export type Language = "en" | "zh";

/** Chinese when the browser prefers it, as the app follows the iPhone's language. */
export function useLanguage(): Language {
  return useSyncExternalStore(
    () => () => {},
    () => (navigator.languages.find((tag) => /^(en|zh)/i.test(tag))?.toLowerCase().startsWith("zh") ? "zh" : "en"),
    () => "en",
  );
}

/** The locale for dates and numbers. */
export function localeFor(language: Language): string {
  if (language === "zh") return "zh-CN";
  // Pages are also rendered on the server, without a browser.
  return (typeof navigator === "undefined" ? undefined : navigator.language) || "en-US";
}

/** The browser locale's first day of the week, 0 = Sunday; Monday where unknown. */
export function weekStartFor(locale: string): number {
  try {
    const info = (new Intl.Locale(locale) as Intl.Locale & {
      getWeekInfo?: () => { firstDay: number };
      weekInfo?: { firstDay: number };
    });
    const firstDay = info.getWeekInfo?.().firstDay ?? info.weekInfo?.firstDay ?? 1;
    return firstDay % 7;
  } catch {
    return 1;
  }
}

const en = {
  overview: "Overview",
  history: "History",
  exercises: "Exercises",
  account: "Account",
  yourTraining: "Your training",
  loading: "Loading your training…",
  loadFailed: "Couldn't load your training. Check your connection and reload the page.",
  noWorkouts: "No workouts yet. Workouts you log in the IronSage iPhone app show up here.",
  workouts: "Workouts",
  thisWeek: "This week",
  weeksInARow: "Weeks in a row",
  weeklyVolume: "Weekly volume",
  weeklyVolumeNote: (unit: string) =>
    `Weight × reps of working sets over the last 12 weeks, in ${unit}. One dumbbell per side counts twice.`,
  body: "Body",
  bodyWeight: "Body weight",
  bodyFat: "Body fat",
  noBodyWeight: "No body weight yet. Enter it in the app, or let it read Apple Health.",
  noBodyFat: "No body fat yet. Smart scales usually save it to Apple Health, where the app reads it.",
  nothingInRange: "Nothing in this period.",
  weeklyAverages: "Weekly averages.",
  period: "Period",
  ranges: { week: "Week", month: "Month", year: "Year", all: "All" },
  recentWorkouts: "Recent workouts",
  allWorkouts: "All workouts",
  weekOf: (range: string) => `Week of ${range}`,
  sets: (count: number) => (count === 1 ? "1 set" : `${count} sets`),
  minutes: (count: number) => `${count} min`,
  inProgress: "In progress",
  warmup: "Warm-up",
  drop: "Drop set",
  failure: "To failure",
  rir: (rir: number) => `RIR ${rir}`,
  volume: "Volume",
  chooseExercise: "Exercise",
  noExercises: "Exercises you log in the app show up here with their progress.",
  estimatedOneRepMax: "Estimated one-rep max",
  estimateNote: "From your best set each session, for sets of 1 to 12 reps.",
  heaviest: "Heaviest",
  bestEstimate: "Best estimated one-rep max",
  fromLift: (lift: string, date: string) => `${lift} on ${date}`,
  sessions: "Sessions",
  readOnly: "To change anything, use the IronSage iPhone app.",
  table: "Values",
  date: "Date",
  week: "Week",
};

const zh: typeof en = {
  overview: "概览",
  history: "历史",
  exercises: "动作",
  account: "账号",
  yourTraining: "你的训练",
  loading: "正在加载你的训练…",
  loadFailed: "无法加载你的训练。请检查网络，然后刷新页面。",
  noWorkouts: "还没有训练记录。你在 IronSage iPhone App 里记录的训练会显示在这里。",
  workouts: "训练次数",
  thisWeek: "本周",
  weeksInARow: "连续周数",
  weeklyVolume: "每周训练量",
  weeklyVolumeNote: (unit: string) =>
    `最近 12 周正式组的重量 × 次数，单位 ${unit}。单只哑铃的动作按两侧计算。`,
  body: "身体",
  bodyWeight: "体重",
  bodyFat: "体脂",
  noBodyWeight: "还没有体重记录。可以在 App 里填写，或让 App 读取 Apple 健康。",
  noBodyFat: "还没有体脂记录。体脂秤通常会把它保存到 Apple 健康，App 会从那里读取。",
  nothingInRange: "这段时间没有记录。",
  weeklyAverages: "每周平均值。",
  period: "时间范围",
  ranges: { week: "周", month: "月", year: "年", all: "全部" },
  recentWorkouts: "最近的训练",
  allWorkouts: "全部训练",
  weekOf: (range: string) => `${range}这一周`,
  sets: (count: number) => `${count} 组`,
  minutes: (count: number) => `${count} 分钟`,
  inProgress: "进行中",
  warmup: "热身",
  drop: "递减组",
  failure: "力竭组",
  rir: (rir: number) => `RIR ${rir}`,
  volume: "训练量",
  chooseExercise: "动作",
  noExercises: "你在 App 里记录的动作会和进步曲线一起显示在这里。",
  estimatedOneRepMax: "估算一次最大重量",
  estimateNote: "取每次训练中最好的一组，只算 1 到 12 次的组。",
  heaviest: "最大重量",
  bestEstimate: "最佳估算一次最大重量",
  fromLift: (lift: string, date: string) => `${date}：${lift}`,
  sessions: "每次训练",
  readOnly: "如需修改，请使用 IronSage iPhone App。",
  table: "数值",
  date: "日期",
  week: "周",
};

export type Strings = typeof en;

export function strings(language: Language): Strings {
  return language === "zh" ? zh : en;
}
