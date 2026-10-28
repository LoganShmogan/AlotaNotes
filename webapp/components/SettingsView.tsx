"use client";
import { useSearchParams } from "next/navigation";
import { useState } from "react";
import { MAX_RETENTION, MIN_RETENTION } from "@/lib/api";
import { useRetention, useTheme, type ThemeChoice } from "@/lib/preferences";
import { PlanPanel } from "./PlanPanel";
import { Card } from "./ui";

const SECTIONS = ["plan", "appearance", "memory"] as const;
type Section = (typeof SECTIONS)[number];
const TITLES: Record<Section, string> = { plan: "Plan", appearance: "Appearance", memory: "Memory" };

/// Settings: one list on phones; a section list beside the section from
/// expanded up, as in the app.
export function SettingsView() {
  const params = useSearchParams();
  const initial = params.get("section");
  const [section, setSection] = useState<Section>(SECTIONS.includes(initial as Section) ? (initial as Section) : "plan");
  const body = (s: Section) =>
    s === "plan" ? <PlanPanel checkout={params.get("checkout")} /> : s === "appearance" ? <Appearance /> : <Memory />;

  return (
    <>
      <div className="flex flex-col gap-6 md:hidden">
        {SECTIONS.map((s) => (
          <section key={s} aria-label={TITLES[s]}>
            <h2 className="mb-2 text-xs font-semibold tracking-wider text-ink-soft uppercase">{TITLES[s]}</h2>
            {body(s)}
          </section>
        ))}
      </div>
      <div className="hidden gap-6 md:grid md:grid-cols-[240px_1fr]">
        <nav aria-label="Settings sections" className="flex flex-col gap-1">
          {SECTIONS.map((s) => (
            <button
              key={s}
              type="button"
              aria-current={s === section ? "true" : undefined}
              onClick={() => setSection(s)}
              className="rounded-[var(--radius-control)] px-3 py-2 text-left hover:bg-tint aria-[current=true]:bg-tint aria-[current=true]:text-fin"
            >
              {TITLES[s]}
            </button>
          ))}
        </nav>
        <section aria-label={TITLES[section]} className="max-w-[640px]">
          <h2 className="mb-3 text-xl font-semibold">{TITLES[section]}</h2>
          {body(section)}
        </section>
      </div>
    </>
  );
}

function Appearance() {
  const [theme, setTheme] = useTheme();
  const options: [ThemeChoice, string][] = [
    ["system", "System"],
    ["light", "Light"],
    ["dark", "Dark"],
  ];
  return (
    <Card>
      <div className="flex gap-2" role="radiogroup" aria-label="Theme">
        {options.map(([value, label]) => (
          <button
            key={value}
            type="button"
            role="radio"
            aria-checked={theme === value}
            onClick={() => setTheme(value)}
            className="flex-1 rounded-[var(--radius-control)] border border-line px-3 py-2 aria-checked:border-fin aria-checked:bg-fin aria-checked:text-on-fin"
          >
            {label}
          </button>
        ))}
      </div>
    </Card>
  );
}

function Memory() {
  const [retention, setRetention] = useRetention();
  const percent = Math.round(retention * 100);
  return (
    <Card className="flex flex-col gap-2">
      <label htmlFor="retention" className="font-semibold">
        Target recall: {percent}%
      </label>
      <p className="text-sm text-ink-soft">
        How likely you should be to still remember something when it comes back. Higher means more frequent reviews. Set per browser, like
        the app sets it per device.
      </p>
      <input
        id="retention"
        type="range"
        min={MIN_RETENTION}
        max={MAX_RETENTION}
        step={0.01}
        value={retention}
        onChange={(e) => setRetention(Number(e.target.value))}
      />
    </Card>
  );
}
