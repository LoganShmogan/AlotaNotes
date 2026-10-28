"use client";
import Link from "next/link";
import { useQuery } from "convex/react";
import { api } from "@/lib/api";
import { forecastByDay, startOfLocalDay, useNow } from "@/lib/time";
import { Card, Pill, SectionLabel, Spinner } from "./ui";

export function TodayDashboard() {
  const now = useNow();
  const dayStart = startOfLocalDay(new Date(now)).toISOString();
  const summary = useQuery(api.today.summary, { now, dayStart });
  if (summary === undefined) return <Spinner />;

  const forecast = forecastByDay(summary.forecast, new Date(now));
  forecast[0].count += summary.dueQuestions + summary.problemsDue.length;
  const peak = Math.max(1, ...forecast.map((d) => d.count));
  const stats = [
    ["Questions due", summary.dueQuestions],
    ["Reviewed today", summary.reviewsToday],
    ["Problems due", summary.problemsDue.length],
    ["Attempts today", summary.attemptsToday],
  ] as const;

  return (
    <div className="grid gap-6 md:grid-cols-[3fr_2fr]">
      <div className="flex flex-col gap-4">
        <Card className="bg-deep text-on-deep">
          {summary.dueQuestions > 0 ? (
            <div className="flex flex-col items-start gap-3">
              <p className="font-display text-3xl font-semibold">{summary.dueQuestions} to review</p>
              <Link href="/quiz" className="rounded-[var(--radius-control)] bg-fin px-4 py-2 font-semibold text-on-fin">
                Start quiz ({summary.dueQuestions})
              </Link>
            </div>
          ) : (
            <div>
              <p className="font-display text-3xl font-semibold">All caught up</p>
              <p className="opacity-80">Nothing to review right now.</p>
            </div>
          )}
        </Card>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {stats.map(([label, value]) => (
            <Card key={label}>
              <p className="font-display text-2xl font-semibold">{value}</p>
              <p className="text-sm text-ink-soft">{label}</p>
            </Card>
          ))}
        </div>
        <section aria-label="Next 7 days">
          <SectionLabel>Next 7 days</SectionLabel>
          <Card className="flex h-40 items-end gap-2">
            {forecast.map((d) => (
              <div key={d.label} className="flex flex-1 flex-col items-center gap-1" title={`${d.label}: ${d.count}`}>
                <span className="text-xs text-ink-soft">{d.count}</span>
                <div className="w-full rounded-t bg-fin" style={{ height: `${(d.count / peak) * 80}px` }} />
                <span className="text-xs">{d.label}</span>
              </div>
            ))}
          </Card>
        </section>
      </div>
      <section>
        <SectionLabel>Problems to re-solve</SectionLabel>
        {summary.problemsDue.length === 0 ? (
          <p className="text-ink-soft">No problems are due.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {summary.problemsDue.map((p) => (
              <li key={p.uid}>
                <Link href={`/tracker?p=${p.uid}`} className="flex items-center justify-between rounded-[var(--radius-card)] border border-line bg-surface p-3 hover:bg-tint">
                  <span>{p.title}</span>
                  <Pill tone={p.difficulty}>{p.difficulty}</Pill>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
