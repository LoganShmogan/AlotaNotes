"use client";
import { useMutation, useQuery } from "convex/react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useMemo, useState } from "react";
import { api, formatInterval, newCard, retrievability, type Rating } from "@/lib/api";
import { messageOf } from "@/lib/errors";
import { useRetention } from "@/lib/preferences";
import { formatDate, relativeTime } from "@/lib/time";
import { RatingButtons } from "./RatingButtons";
import { Button, Card, Dialog, EmptyState, ErrorText, Field, inputClass, Pill, SectionLabel, Spinner } from "./ui";

type ProblemSummary = NonNullable<ReturnType<typeof useQuery<typeof api.problems.list>>>[number];
type Filter = "all" | "due" | "new" | "easy" | "medium" | "hard";
const FILTERS: [Filter, string][] = [
  ["all", "All"],
  ["due", "Due"],
  ["new", "Not tried"],
  ["easy", "Easy"],
  ["medium", "Medium"],
  ["hard", "Hard"],
];

export function matches(p: ProblemSummary, filter: Filter, search: string, now: number): boolean {
  const s = search.trim().toLowerCase();
  if (s && !p.title.toLowerCase().includes(s) && !p.tags.some((t) => t.includes(s))) return false;
  switch (filter) {
    case "due":
      return p.card !== null && p.card.due <= now;
    case "new":
      return p.card === null;
    case "easy":
    case "medium":
    case "hard":
      return p.difficulty === filter;
    default:
      return true;
  }
}

/// The tracker (Docs/quillfin_plan.md §5): cards on phones, list and detail
/// side by side from expanded up, and a sortable table on large windows.
export function Tracker() {
  const params = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const selected = params.get("p");
  const problems = useQuery(api.problems.list, {});
  const [filter, setFilter] = useState<Filter>("all");
  const [search, setSearch] = useState("");
  const [table, setTable] = useState(false);
  const [adding, setAdding] = useState(false);
  const [now] = useState(() => Date.now());
  const open = (uid: string | null) => router.push(uid ? `${pathname}?p=${uid}` : pathname);
  const shown = useMemo(() => (problems ?? []).filter((p) => matches(p, filter, search, now)), [problems, filter, search, now]);

  if (problems === undefined) return <Spinner />;

  return (
    <div className="grid gap-6 md:grid-cols-[minmax(320px,2fr)_3fr]">
      <div className={selected ? "hidden md:block" : ""}>
        <div className="mb-3 flex flex-wrap items-center gap-2">
          <input aria-label="Search problems" placeholder="Search titles and tags" className={`${inputClass} flex-1`} value={search} onChange={(e) => setSearch(e.target.value)} />
          <Button onClick={() => setAdding(true)}>Add problem</Button>
          <Button variant="outline" className="hidden lg:inline-flex" onClick={() => setTable((t) => !t)}>
            {table ? "Cards" : "Table"}
          </Button>
        </div>
        <div className="mb-3 flex gap-2 overflow-x-auto pb-1" role="group" aria-label="Filter">
          {FILTERS.map(([f, label]) => (
            <button
              key={f}
              type="button"
              aria-pressed={filter === f}
              onClick={() => setFilter(f)}
              className="shrink-0 rounded-full border border-line px-3 py-1 text-sm aria-pressed:border-fin aria-pressed:bg-fin aria-pressed:text-on-fin"
            >
              {label}
            </button>
          ))}
        </div>
        {problems.length === 0 ? (
          <EmptyState title="No problems yet">Add one you&apos;re practising, then log each attempt.</EmptyState>
        ) : shown.length === 0 ? (
          <p className="text-ink-soft">Nothing matches.</p>
        ) : table ? (
          <ProblemTable problems={shown} now={now} open={open} />
        ) : (
          <ul className="flex flex-col gap-2" aria-label="Problems">
            {shown.map((p) => (
              <li key={p.uid}>
                <button
                  type="button"
                  onClick={() => open(p.uid)}
                  aria-current={p.uid === selected ? "true" : undefined}
                  className="w-full rounded-[var(--radius-card)] border border-line bg-surface p-3 text-left hover:bg-tint aria-[current=true]:border-fin"
                >
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-semibold">{p.title}</span>
                    <Pill tone={p.difficulty}>{p.difficulty}</Pill>
                  </div>
                  <p className="mt-1 text-sm text-ink-soft">
                    {p.card === null ? "Not tried yet" : p.card.due <= now ? "Due now" : `Due ${relativeTime(new Date(p.card.due).toISOString(), now, formatInterval)}`}
                    {p.attempts > 0 && ` · ${p.attempts} attempt${p.attempts === 1 ? "" : "s"}`}
                  </p>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
      <div className={selected ? "" : "hidden md:block"}>
        {selected ? <ProblemDetail key={selected} uid={selected} onBack={() => open(null)} /> : <EmptyState title="Select a problem to see it here." />}
      </div>
      {adding && <ProblemForm onClose={() => setAdding(false)} onSaved={(uid) => open(uid)} />}
    </div>
  );
}

type SortKey = "title" | "difficulty" | "due" | "recall" | "attempts";
const DIFFICULTY_ORDER = { easy: 0, medium: 1, hard: 2 };

export function sortProblems(problems: ProblemSummary[], key: SortKey, now: number): ProblemSummary[] {
  const value = (p: ProblemSummary): number | string => {
    switch (key) {
      case "title":
        return p.title.toLowerCase();
      case "difficulty":
        return DIFFICULTY_ORDER[p.difficulty];
      case "due":
        return p.card?.due ?? Number.MAX_SAFE_INTEGER;
      case "recall":
        return p.card ? retrievability(p.card, now) : -1;
      case "attempts":
        return p.attempts;
    }
  };
  return [...problems].sort((a, b) => (value(a) < value(b) ? -1 : value(a) > value(b) ? 1 : 0));
}

function ProblemTable({ problems, now, open }: { problems: ProblemSummary[]; now: number; open: (uid: string) => void }) {
  const [key, setKey] = useState<SortKey>("due");
  const header = (k: SortKey, label: string) => (
    <th scope="col" className="px-2 py-2 text-left">
      <button type="button" onClick={() => setKey(k)} className={key === k ? "font-semibold text-fin" : "font-semibold"}>
        {label}
      </button>
    </th>
  );
  return (
    <table className="w-full text-sm">
      <thead className="border-b border-line">
        <tr>
          {header("title", "Name")}
          {header("difficulty", "Difficulty")}
          {header("due", "Next due")}
          {header("recall", "Recall")}
          {header("attempts", "Attempts")}
        </tr>
      </thead>
      <tbody>
        {sortProblems(problems, key, now).map((p) => (
          <tr key={p.uid} onClick={() => open(p.uid)} className="cursor-pointer border-b border-line hover:bg-tint">
            <td className="px-2 py-2">{p.title}</td>
            <td className="px-2 py-2">
              <Pill tone={p.difficulty}>{p.difficulty}</Pill>
            </td>
            <td className="px-2 py-2">{p.card ? formatDate(new Date(p.card.due).toISOString()) : "—"}</td>
            <td className="px-2 py-2">{p.card ? `${Math.round(retrievability(p.card, now) * 100)}%` : "—"}</td>
            <td className="px-2 py-2">{p.attempts}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function ProblemDetail({ uid, onBack }: { uid: string; onBack: () => void }) {
  const problem = useQuery(api.problems.get, { uid });
  const remove = useMutation(api.problems.remove);
  const [editing, setEditing] = useState(false);
  const [logging, setLogging] = useState(false);
  const [now] = useState(() => Date.now());
  if (problem === undefined) return <Spinner />;
  if (problem === null) return <EmptyState title="This problem no longer exists." />;
  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-2">
        <Button variant="ghost" className="md:hidden" onClick={onBack}>
          ← Back
        </Button>
        <div className="ml-auto flex gap-2">
          <Button variant="ghost" onClick={() => setEditing(true)}>
            Edit
          </Button>
          <Button
            variant="ghost"
            className="text-danger"
            onClick={async () => {
              if (!window.confirm(`Delete “${problem.title}” and its attempts?`)) return;
              await remove({ uid });
              onBack();
            }}
          >
            Delete
          </Button>
        </div>
      </div>
      <div>
        <h2 className="text-2xl font-semibold">{problem.title}</h2>
        <div className="mt-2 flex flex-wrap items-center gap-2">
          <Pill tone={problem.difficulty}>{problem.difficulty}</Pill>
          {problem.platform && <Pill>{problem.platform}</Pill>}
          {problem.tags.map((t) => (
            <Pill key={t}>{t}</Pill>
          ))}
          {problem.url && (
            <a href={problem.url} target="_blank" rel="noopener noreferrer" className="text-sm text-fin underline">
              Open problem
            </a>
          )}
        </div>
      </div>
      <Card className="grid grid-cols-2 gap-2 sm:grid-cols-3">
        <div>
          <p className="text-xs text-ink-soft">Next due</p>
          <p className="font-semibold">{problem.card ? relativeTime(new Date(problem.card.due).toISOString(), now, formatInterval) : "Not tried yet"}</p>
        </div>
        <div>
          <p className="text-xs text-ink-soft">Recall now</p>
          <p className="font-semibold">{problem.card ? `${Math.round(retrievability(problem.card, now) * 100)}%` : "—"}</p>
        </div>
        <div>
          <p className="text-xs text-ink-soft">Attempts</p>
          <p className="font-semibold">{problem.attempts.length}</p>
        </div>
      </Card>
      <Button onClick={() => setLogging(true)}>Log attempt</Button>
      {problem.solution && (
        <section>
          <SectionLabel>Solution</SectionLabel>
          <pre className="overflow-x-auto rounded-[var(--radius-card)] bg-tint p-3 text-sm whitespace-pre-wrap">{problem.solution}</pre>
        </section>
      )}
      {problem.notes && (
        <section>
          <SectionLabel>Notes</SectionLabel>
          <p className="whitespace-pre-wrap">{problem.notes}</p>
        </section>
      )}
      <section>
        <SectionLabel>Attempts</SectionLabel>
        {problem.attempts.length === 0 ? (
          <p className="text-ink-soft">No attempts yet.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {problem.attempts.map((a) => (
              <li key={a.uid} className="rounded-[var(--radius-card)] border border-line bg-surface p-3 text-sm">
                <span className={a.solved ? "font-semibold text-success" : "font-semibold text-danger"}>{a.solved ? "Solved" : "Not solved"}</span>
                {` · ${formatDate(a.attemptedAt)}`}
                {a.durationMinutes !== null && ` · ${a.durationMinutes} min`}
                {a.notes && <p className="mt-1 text-ink-soft">{a.notes}</p>}
              </li>
            ))}
          </ul>
        )}
      </section>
      {editing && <ProblemForm problem={problem} onClose={() => setEditing(false)} />}
      {logging && <LogAttempt problem={problem} onClose={() => setLogging(false)} />}
    </div>
  );
}

type FullProblem = NonNullable<ReturnType<typeof useQuery<typeof api.problems.get>>>;

function ProblemForm({ problem, onClose, onSaved }: { problem?: FullProblem; onClose: () => void; onSaved?: (uid: string) => void }) {
  const create = useMutation(api.problems.create);
  const update = useMutation(api.problems.update);
  const [form, setForm] = useState({
    title: problem?.title ?? "",
    difficulty: problem?.difficulty ?? ("medium" as const),
    url: problem?.url ?? "",
    platform: problem?.platform ?? "",
    tags: problem?.tags.join(", ") ?? "",
    solution: problem?.solution ?? "",
    notes: problem?.notes ?? "",
  });
  const [error, setError] = useState<string | null>(null);
  const set = (key: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) =>
    setForm({ ...form, [key]: e.target.value });
  return (
    <Dialog open onClose={onClose} title={problem ? "Edit problem" : "Add a problem"}>
      <form
        className="flex flex-col gap-3"
        onSubmit={async (e) => {
          e.preventDefault();
          const args = { ...form, url: form.url || null, tags: form.tags.split(",") };
          try {
            if (problem) await update({ uid: problem.uid, ...args });
            else onSaved?.(await create(args));
            onClose();
          } catch (err) {
            setError(messageOf(err));
          }
        }}
      >
        <Field label="Title">
          <input className={inputClass} value={form.title} onChange={set("title")} required />
        </Field>
        <Field label="Difficulty">
          <select className={inputClass} value={form.difficulty} onChange={set("difficulty")}>
            <option value="easy">Easy</option>
            <option value="medium">Medium</option>
            <option value="hard">Hard</option>
          </select>
        </Field>
        <Field label="Link">
          <input className={inputClass} value={form.url} onChange={set("url")} placeholder="https://leetcode.com/problems/..." />
        </Field>
        <Field label="Platform">
          <input className={inputClass} value={form.platform} onChange={set("platform")} />
        </Field>
        <Field label="Tags" hint="Comma-separated">
          <input className={inputClass} value={form.tags} onChange={set("tags")} />
        </Field>
        <Field label="Solution">
          <textarea className={`${inputClass} font-mono`} value={form.solution} onChange={set("solution")} />
        </Field>
        <Field label="Notes">
          <textarea className={inputClass} value={form.notes} onChange={set("notes")} />
        </Field>
        <ErrorText>{error}</ErrorText>
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit">Save</Button>
        </div>
      </form>
    </Dialog>
  );
}

function LogAttempt({ problem, onClose }: { problem: FullProblem; onClose: () => void }) {
  const log = useMutation(api.problems.logAttempt);
  const [retention] = useRetention();
  const [solved, setSolved] = useState(true);
  const [minutes, setMinutes] = useState("");
  const [notes, setNotes] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [now] = useState(() => Date.now());
  const rate = async (rating: Rating) => {
    const duration = minutes.trim() === "" ? null : Number(minutes);
    if (duration !== null && !(Number.isInteger(duration) && duration >= 0)) return setError("Time taken must be a whole number of minutes.");
    setBusy(true);
    try {
      await log({ uid: problem.uid, solved, rating, durationMinutes: duration, notes, retention });
      onClose();
    } catch (e) {
      setError(messageOf(e));
      setBusy(false);
    }
  };
  return (
    <Dialog open onClose={onClose} title={`Log an attempt: ${problem.title}`}>
      <div className="flex gap-2" role="group" aria-label="Result">
        {[true, false].map((value) => (
          <button
            key={String(value)}
            type="button"
            aria-pressed={solved === value}
            onClick={() => setSolved(value)}
            className="flex-1 rounded-[var(--radius-control)] border border-line px-3 py-2 aria-pressed:border-fin aria-pressed:bg-fin aria-pressed:text-on-fin"
          >
            {value ? "Solved" : "Not solved"}
          </button>
        ))}
      </div>
      <Field label="Minutes taken (optional)">
        <input className={inputClass} inputMode="numeric" value={minutes} onChange={(e) => setMinutes(e.target.value)} />
      </Field>
      <Field label="Notes (optional)">
        <textarea className={inputClass} value={notes} onChange={(e) => setNotes(e.target.value)} />
      </Field>
      <p className="text-sm font-medium">How hard was it to recall?</p>
      <RatingButtons card={problem.card ?? newCard(now)} now={now} retention={retention} disabled={busy} onRate={rate} />
      <ErrorText>{error}</ErrorText>
    </Dialog>
  );
}
