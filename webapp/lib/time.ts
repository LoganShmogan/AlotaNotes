"use client";
import { useEffect, useState } from "react";

const DAY = 86_400_000;

/// The current time, ticking every [everyMs] (a minute by default), as an
/// ISO string: stable between ticks, so queries that take it stay cached.
export function useNow(everyMs = 60_000): string {
  const [now, setNow] = useState(() => roundDown(Date.now(), everyMs));
  useEffect(() => {
    const id = setInterval(() => setNow(roundDown(Date.now(), everyMs)), everyMs);
    return () => clearInterval(id);
  }, [everyMs]);
  return now;
}

const roundDown = (ms: number, step: number) => new Date(Math.floor(ms / step) * step).toISOString();

/// Midnight at the start of the viewer's local day containing [at].
export function startOfLocalDay(at: Date): Date {
  return new Date(at.getFullYear(), at.getMonth(), at.getDate());
}

/// How many of [dueTimes] fall on each of the next [days] local days,
/// starting today.
export function forecastByDay(dueTimes: string[], now: Date, days = 7): { label: string; count: number }[] {
  const start = startOfLocalDay(now);
  const buckets = Array.from({ length: days }, (_, i) => {
    const day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
    return {
      label: i === 0 ? "Today" : day.toLocaleDateString(undefined, { weekday: "short" }),
      start: day.getTime(),
      count: 0,
    };
  });
  const end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + days).getTime();
  for (const due of dueTimes) {
    const t = Date.parse(due);
    // The server looks 7 x 24 h ahead, which reaches into an eighth day.
    if (t >= end) continue;
    for (let i = buckets.length - 1; i >= 0; i--) {
      if (t >= buckets[i].start) {
        buckets[i].count++;
        break;
      }
    }
  }
  return buckets.map(({ label, count }) => ({ label, count }));
}

/// "now", "in 10m", "in 3d", "2d ago".
export function relativeTime(iso: string, now: number, format: (ms: number) => string): string {
  const diff = Date.parse(iso) - now;
  if (Math.abs(diff) < 60_000) return "now";
  return diff > 0 ? `in ${format(diff)}` : `${format(-diff)} ago`;
}

export const formatDate = (iso: string) =>
  new Date(iso).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" });

export { DAY };
