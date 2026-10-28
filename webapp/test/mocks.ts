// State behind the Convex and Next navigation stand-ins registered in
// setup.ts: components render against canned query results, and their
// calls are recorded.
import { vi } from "vitest";

export const backend = {
  queries: new Map<string, unknown>(),
  handlers: new Map<string, (args: Record<string, unknown>) => unknown>(),
  calls: [] as { name: string; args: Record<string, unknown> }[],
  reset() {
    this.queries.clear();
    this.handlers.clear();
    this.calls.length = 0;
  },
};

export const nav = {
  pathname: "/",
  params: new URLSearchParams(),
  push: vi.fn(),
  replace: vi.fn(),
};

/// Queries answer with [value] (or a function of the args).
export function answer(name: string, value: unknown) {
  backend.queries.set(name, value);
}

export function handle(name: string, fn: (args: Record<string, unknown>) => unknown) {
  backend.handlers.set(name, fn);
}

export const calls = (name: string) => backend.calls.filter((c) => c.name === name).map((c) => c.args);

export function at(pathname: string, query = "") {
  nav.pathname = pathname;
  nav.params = new URLSearchParams(query);
  nav.push.mockClear();
}
