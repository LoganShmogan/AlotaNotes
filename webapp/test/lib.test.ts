import { act, renderHook } from "@testing-library/react";
import { ConvexError } from "convex/values";
import { describe, expect, test, vi } from "vitest";
import { codeOf, messageOf } from "@/lib/errors";
import { applyTheme, readRetention, readTheme, themeBootScript, useRetention, useTheme } from "@/lib/preferences";
import { forecastByDay, formatDate, relativeTime, startOfLocalDay, useNow } from "@/lib/time";
import { formatInterval } from "@/lib/api";

describe("time", () => {
  test("buckets due times into the next seven local days", () => {
    const now = new Date(2026, 9, 28, 15);
    const at = (days: number, hour: number) => new Date(2026, 9, 28 + days, hour).toISOString();
    const days = forecastByDay([at(0, 18), at(1, 1), at(1, 23), at(6, 9), at(9, 9)], now);
    expect(days).toHaveLength(7);
    expect(days[0]).toEqual({ label: "Today", count: 1 });
    expect(days.map((d) => d.count)).toEqual([1, 2, 0, 0, 0, 0, 1]);
  });

  test("relative times and dates", () => {
    const now = Date.UTC(2026, 9, 28);
    expect(relativeTime(new Date(now + 30_000).toISOString(), now, formatInterval)).toBe("now");
    expect(relativeTime(new Date(now + 3 * 86_400_000).toISOString(), now, formatInterval)).toBe("in 3d");
    expect(relativeTime(new Date(now - 2 * 3_600_000).toISOString(), now, formatInterval)).toBe("2h ago");
    expect(formatDate("2026-10-28T12:00:00.000Z")).toMatch(/2026/);
    expect(startOfLocalDay(new Date(2026, 9, 28, 15, 30)).getHours()).toBe(0);
  });

  test("useNow ticks on the minute and is stable in between", () => {
    vi.useFakeTimers();
    vi.setSystemTime(Date.UTC(2026, 9, 28, 9, 0, 30));
    const { result, unmount } = renderHook(() => useNow());
    expect(result.current).toBe("2026-10-28T09:00:00.000Z");
    act(() => vi.advanceTimersByTime(60_000));
    expect(result.current).toBe("2026-10-28T09:01:00.000Z");
    unmount();
    vi.useRealTimers();
  });
});

describe("preferences", () => {
  test("target recall defaults to 90%, saves, and ignores bad values", () => {
    expect(readRetention()).toBe(0.9);
    const { result } = renderHook(() => useRetention());
    act(() => result.current[1](0.85));
    expect(result.current[0]).toBe(0.85);
    window.localStorage.setItem("quillfin.retention", "5");
    expect(readRetention()).toBe(0.9);
  });

  test("the theme is applied to <html> and remembered", () => {
    const { result } = renderHook(() => useTheme());
    expect(result.current[0]).toBe("system");
    act(() => result.current[1]("dark"));
    expect(document.documentElement.dataset.theme).toBe("dark");
    expect(readTheme()).toBe("dark");
    applyTheme("system");
    expect(document.documentElement.hasAttribute("data-theme")).toBe(false);
    expect(themeBootScript).toContain("quillfin.theme");
  });

  test("storage that throws falls back to the defaults", () => {
    const spy = vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("blocked");
    });
    const set = vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("blocked");
    });
    expect(readRetention()).toBe(0.9);
    expect(readTheme()).toBe("system");
    const { result } = renderHook(() => useRetention());
    act(() => result.current[1](0.8));
    spy.mockRestore();
    set.mockRestore();
  });
});

describe("errors", () => {
  test("shows the backend's message and code", () => {
    const e = new ConvexError({ code: "AI_LIMIT_REACHED", message: "You've used all 20." });
    expect(messageOf(e)).toBe("You've used all 20.");
    expect(codeOf(e)).toBe("AI_LIMIT_REACHED");
    expect(messageOf(new ConvexError("plain"))).toBe("plain");
    expect(messageOf(new ConvexError({ code: "X" }))).toBe("Something went wrong. Try again.");
    expect(messageOf(new Error("boom"))).toBe("Something went wrong. Try again.");
    expect(codeOf(new Error("boom"))).toBeNull();
    expect(codeOf(new ConvexError({ message: "m" }))).toBeNull();
  });
});
