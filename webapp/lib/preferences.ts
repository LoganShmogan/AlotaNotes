"use client";
// Per-browser preferences, as Settings keeps them on each device in the app:
// target recall and the theme. Storage can be unavailable (private windows),
// so every access is guarded and falls back to the default.
import { useCallback, useSyncExternalStore } from "react";
import { DEFAULT_RETENTION, MAX_RETENTION, MIN_RETENTION } from "./api";

export type ThemeChoice = "system" | "light" | "dark";

const RETENTION_KEY = "quillfin.retention";
export const THEME_KEY = "quillfin.theme";
const listeners = new Set<() => void>();

function read(key: string): string | null {
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

function write(key: string, value: string) {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    // Not saved; the choice still applies until the page is reloaded.
  }
  listeners.forEach((l) => l());
}

const subscribe = (l: () => void) => {
  listeners.add(l);
  return () => listeners.delete(l);
};

export function readRetention(): number {
  const value = Number(read(RETENTION_KEY));
  return value >= MIN_RETENTION && value <= MAX_RETENTION ? value : DEFAULT_RETENTION;
}

export function useRetention(): [number, (value: number) => void] {
  const value = useSyncExternalStore(subscribe, readRetention, () => DEFAULT_RETENTION);
  const set = useCallback((v: number) => write(RETENTION_KEY, String(v)), []);
  return [value, set];
}

export function readTheme(): ThemeChoice {
  const value = read(THEME_KEY);
  return value === "light" || value === "dark" ? value : "system";
}

export function applyTheme(choice: ThemeChoice) {
  if (choice === "system") document.documentElement.removeAttribute("data-theme");
  else document.documentElement.setAttribute("data-theme", choice);
}

export function useTheme(): [ThemeChoice, (value: ThemeChoice) => void] {
  const value = useSyncExternalStore(subscribe, readTheme, () => "system" as ThemeChoice);
  const set = useCallback((v: ThemeChoice) => {
    write(THEME_KEY, v);
    applyTheme(v);
  }, []);
  return [value, set];
}

/// Inlined in <head> so the saved theme applies before the first paint.
export const themeBootScript = `try{var t=localStorage.getItem("${THEME_KEY}");if(t==="light"||t==="dark")document.documentElement.setAttribute("data-theme",t)}catch(e){}`;
