import type { Range } from "../lib/training";

/** "Oct 20" / "10月20日" */
export function shortDay(date: Date, locale: string): string {
  return date.toLocaleDateString(locale, { month: "short", day: "numeric" });
}

/** "Tue, Oct 20, 2026" */
export function fullDay(date: Date, locale: string): string {
  return date.toLocaleDateString(locale, { weekday: "short", month: "short", day: "numeric", year: "numeric" });
}

/** "Oct 19 – 25", the seven days from `start`. */
export function weekRange(start: Date, locale: string): string {
  const end = new Date(start);
  end.setDate(end.getDate() + 6);
  return new Intl.DateTimeFormat(locale, { month: "short", day: "numeric" }).formatRange(start, end);
}

/** Axis labels that fit the period shown. */
export function axisDate(date: Date, range: Range, locale: string): string {
  switch (range) {
    case "week":
      return date.toLocaleDateString(locale, { weekday: "short" });
    case "month":
      return shortDay(date, locale);
    case "year":
      return date.toLocaleDateString(locale, { month: "short" });
    case "all":
      return date.toLocaleDateString(locale, { month: "short", year: "2-digit" });
  }
}

/** Whole numbers with the locale's grouping: "12,400". */
export function wholeNumber(value: number, locale: string): string {
  return Math.round(value).toLocaleString(locale);
}

/** "18.5%" */
export function percent(value: number, locale: string): string {
  return (value / 100).toLocaleString(locale, { style: "percent", maximumFractionDigits: 1 });
}
