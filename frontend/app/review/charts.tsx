"use client";

import { useEffect, useRef, useState, type KeyboardEvent, type PointerEvent } from "react";

import type { Point } from "../lib/training";

// Hand-built SVG charts in the app's style: one series in the chart red, thin marks,
// recessive grid, a readout on hover and keyboard focus, and a table for screen readers.

const HEIGHT = 180;
const MARGIN = { top: 12, right: 12, bottom: 26, left: 44 };

/** The width the chart has, so text in the SVG keeps its size. */
function useWidth() {
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    const observer = new ResizeObserver(([entry]) => setWidth(entry.contentRect.width));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  return { ref, width };
}

/** About `count` round values covering min…max. */
export function niceTicks(min: number, max: number, count = 4): number[] {
  if (min === max) {
    const pad = Math.abs(min) * 0.05 || 1;
    min -= pad;
    max += pad;
  }
  const raw = (max - min) / count;
  const power = 10 ** Math.floor(Math.log10(raw));
  // No 2.5: labels rounded to one decimal would show 78.3 for 78.25.
  const step = [1, 2, 5, 10].map((factor) => factor * power).find((s) => s >= raw) ?? raw;
  const ticks: number[] = [];
  for (let value = Math.floor(min / step) * step; value <= max + step * 0.5; value += step) {
    ticks.push(Number(value.toFixed(10)));
  }
  if (ticks[ticks.length - 1] < max) ticks.push(ticks[ticks.length - 1] + step);
  return ticks;
}

function Readout({ x, width, value, detail }: { x: number; width: number; value: string; detail: string }) {
  const left = Math.min(Math.max(x, 70), Math.max(width - 70, 70));
  return (
    <div
      aria-hidden
      className="pointer-events-none absolute bottom-full z-10 mb-1 -translate-x-1/2 rounded-sm border border-ink/15 bg-card px-2.5 py-1.5 text-center shadow-sm"
      style={{ left }}
    >
      <div className="text-sm font-semibold tabular-nums">{value}</div>
      <div className="text-xs text-steel">{detail}</div>
    </div>
  );
}

function ScreenReaderTable({ caption, rows, head }: { caption: string; head: [string, string]; rows: [string, string][] }) {
  return (
    <table className="sr-only">
      <caption>{caption}</caption>
      <thead>
        <tr>
          <th scope="col">{head[0]}</th>
          <th scope="col">{head[1]}</th>
        </tr>
      </thead>
      <tbody>
        {rows.map(([a, b], index) => (
          <tr key={index}>
            <td>{a}</td>
            <td>{b}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

export function LineChart({
  points,
  start,
  end,
  title,
  formatValue,
  formatAxisDate,
  formatDate,
  dateHeading,
}: {
  points: Point[];
  start: Date;
  end: Date;
  title: string;
  formatValue: (value: number) => string;
  formatAxisDate: (date: Date) => string;
  formatDate: (date: Date) => string;
  dateHeading: string;
}) {
  const { ref, width } = useWidth();
  const [active, setActive] = useState<number | null>(null);

  const values = points.map((point) => point.value);
  const ticks = niceTicks(Math.min(...values), Math.max(...values));
  const [low, high] = [ticks[0], ticks[ticks.length - 1]];
  const plotWidth = Math.max(width - MARGIN.left - MARGIN.right, 1);
  const plotHeight = HEIGHT - MARGIN.top - MARGIN.bottom;
  const span = Math.max(end.getTime() - start.getTime(), 86_400_000);
  const x = (date: Date) => MARGIN.left + ((date.getTime() - start.getTime()) / span) * plotWidth;
  const y = (value: number) => MARGIN.top + (1 - (value - low) / (high - low)) * plotHeight;
  const path = points.map((point, index) => `${index ? "L" : "M"}${x(point.date)},${y(point.value)}`).join("");
  const axisDates = Array.from({ length: 4 }, (_, index) => new Date(start.getTime() + (span * (index + 0.5)) / 4));

  function nearest(event: PointerEvent<SVGRectElement>) {
    const bounds = event.currentTarget.getBoundingClientRect();
    const time = start.getTime() + ((event.clientX - bounds.left) / bounds.width) * span;
    let best = 0;
    points.forEach((point, index) => {
      if (Math.abs(point.date.getTime() - time) < Math.abs(points[best].date.getTime() - time)) best = index;
    });
    setActive(best);
  }

  function onKeyDown(event: KeyboardEvent) {
    if (event.key === "ArrowLeft") setActive((index) => Math.max((index ?? points.length) - 1, 0));
    else if (event.key === "ArrowRight") setActive((index) => Math.min((index ?? -1) + 1, points.length - 1));
    else return;
    event.preventDefault();
  }

  const shown = active === null ? null : points[active];

  return (
    <div ref={ref} className="relative">
      {width > 0 ? (
        <svg
          width={width}
          height={HEIGHT}
          role="img"
          aria-label={title}
          tabIndex={0}
          onKeyDown={onKeyDown}
          onFocus={() => setActive(points.length - 1)}
          onBlur={() => setActive(null)}
          className="block overflow-visible focus-visible:outline-offset-4"
        >
          {ticks.map((tick) => (
            <g key={tick}>
              <line x1={MARGIN.left} x2={width - MARGIN.right} y1={y(tick)} y2={y(tick)} className="stroke-ink/10" strokeWidth={1} />
              <text x={MARGIN.left - 8} y={y(tick)} dy="0.32em" textAnchor="end" className="fill-steel text-[11px] tabular-nums">
                {formatValue(tick)}
              </text>
            </g>
          ))}
          {axisDates.map((date) => (
            <text key={date.getTime()} x={x(date)} y={HEIGHT - 6} textAnchor="middle" className="fill-steel text-[11px]">
              {formatAxisDate(date)}
            </text>
          ))}
          <path d={path} fill="none" stroke="var(--chart-mark)" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
          {points.length === 1 || !shown ? (
            <circle
              cx={x(points[points.length - 1].date)}
              cy={y(points[points.length - 1].value)}
              r={4}
              fill="var(--chart-mark)"
              stroke="var(--card)"
              strokeWidth={2}
            />
          ) : null}
          {shown ? (
            <g>
              <line x1={x(shown.date)} x2={x(shown.date)} y1={MARGIN.top} y2={HEIGHT - MARGIN.bottom} className="stroke-ink/30" strokeWidth={1} />
              <circle cx={x(shown.date)} cy={y(shown.value)} r={4.5} fill="var(--chart-mark)" stroke="var(--card)" strokeWidth={2} />
            </g>
          ) : null}
          <rect
            x={MARGIN.left}
            y={0}
            width={plotWidth}
            height={HEIGHT}
            fill="transparent"
            onPointerMove={nearest}
            onPointerLeave={() => setActive(null)}
          />
        </svg>
      ) : (
        <div style={{ height: HEIGHT }} />
      )}
      {shown ? <Readout x={x(shown.date)} width={width} value={formatValue(shown.value)} detail={formatDate(shown.date)} /> : null}
      <ScreenReaderTable
        caption={title}
        head={[dateHeading, title]}
        rows={points.map((point) => [formatDate(point.date), formatValue(point.value)])}
      />
    </div>
  );
}

export interface Bar {
  axisLabel: string;
  label: string;
  value: number;
}

export function BarChart({
  bars,
  title,
  formatValue,
  labelHeading,
}: {
  bars: Bar[];
  title: string;
  formatValue: (value: number) => string;
  labelHeading: string;
}) {
  const { ref, width } = useWidth();
  const [active, setActive] = useState<number | null>(null);

  const ticks = niceTicks(0, Math.max(...bars.map((bar) => bar.value), 1));
  const high = ticks[ticks.length - 1];
  const plotWidth = Math.max(width - MARGIN.left - MARGIN.right, 1);
  const plotHeight = HEIGHT - MARGIN.top - MARGIN.bottom;
  const column = plotWidth / bars.length;
  const gap = Math.max(2, column * 0.25);
  const y = (value: number) => MARGIN.top + (1 - value / high) * plotHeight;
  const base = y(0);
  const labelEvery = Math.ceil(bars.length / Math.max(Math.floor(plotWidth / 56), 1));

  function barPath(left: number, barWidth: number, top: number) {
    const radius = Math.min(4, barWidth / 2, base - top);
    if (base - top <= 0) return "";
    return `M${left},${base}V${top + radius}Q${left},${top} ${left + radius},${top}H${left + barWidth - radius}Q${left + barWidth},${top} ${left + barWidth},${top + radius}V${base}Z`;
  }

  const shown = active === null ? null : bars[active];

  return (
    <div ref={ref} className="relative">
      {width > 0 ? (
        <svg width={width} height={HEIGHT} role="group" aria-label={title} className="block overflow-visible">
          {ticks.map((tick) => (
            <g key={tick}>
              <line x1={MARGIN.left} x2={width - MARGIN.right} y1={y(tick)} y2={y(tick)} className="stroke-ink/10" strokeWidth={1} />
              <text x={MARGIN.left - 8} y={y(tick)} dy="0.32em" textAnchor="end" className="fill-steel text-[11px] tabular-nums">
                {formatValue(tick)}
              </text>
            </g>
          ))}
          {bars.map((bar, index) => {
            const left = MARGIN.left + index * column + gap / 2;
            const barWidth = column - gap;
            return (
              <g
                key={index}
                tabIndex={0}
                role="img"
                aria-label={`${bar.label}: ${formatValue(bar.value)}`}
                onPointerEnter={() => setActive(index)}
                onPointerLeave={() => setActive(null)}
                onFocus={() => setActive(index)}
                onBlur={() => setActive(null)}
                className="outline-none"
              >
                <rect x={MARGIN.left + index * column} y={MARGIN.top} width={column} height={plotHeight} fill="transparent" />
                <path
                  d={barPath(left, barWidth, y(bar.value))}
                  fill="var(--chart-mark)"
                  opacity={active === null || active === index ? 1 : 0.55}
                />
                {active === index ? (
                  <rect x={left - 2} y={MARGIN.top} width={barWidth + 4} height={plotHeight} fill="none" className="stroke-ink/30" strokeWidth={1} rx={4} />
                ) : null}
                {index % labelEvery === (bars.length - 1) % labelEvery ? (
                  <text x={left + barWidth / 2} y={HEIGHT - 6} textAnchor="middle" className="fill-steel text-[11px]">
                    {bar.axisLabel}
                  </text>
                ) : null}
              </g>
            );
          })}
          <line x1={MARGIN.left} x2={width - MARGIN.right} y1={base} y2={base} className="stroke-ink/30" strokeWidth={1} />
        </svg>
      ) : (
        <div style={{ height: HEIGHT }} />
      )}
      {shown && active !== null ? (
        <Readout
          x={MARGIN.left + (active + 0.5) * column}
          width={width}
          value={formatValue(shown.value)}
          detail={shown.label}
        />
      ) : null}
      <ScreenReaderTable caption={title} head={[labelHeading, title]} rows={bars.map((bar) => [bar.label, formatValue(bar.value)])} />
    </div>
  );
}
