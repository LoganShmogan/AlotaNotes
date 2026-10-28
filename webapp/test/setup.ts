import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { getFunctionName } from "convex/server";
import { afterEach, vi } from "vitest";
import { backend, nav } from "./mocks";

afterEach(() => {
  cleanup();
  window.localStorage.clear();
});

vi.mock("convex/react", () => {
  const call = (ref: unknown) => async (args: Record<string, unknown> = {}) => {
    const name = getFunctionName(ref as never);
    backend.calls.push({ name, args });
    const handler = backend.handlers.get(name);
    return handler ? handler(args) : null;
  };
  return {
    useQuery: (ref: unknown, args: Record<string, unknown> = {}) => {
      const value = backend.queries.get(getFunctionName(ref as never));
      return typeof value === "function" ? (value as (a: unknown) => unknown)(args) : value;
    },
    useMutation: call,
    useAction: call,
  };
});

vi.mock("next/navigation", () => ({
  usePathname: () => nav.pathname,
  useSearchParams: () => nav.params,
  useRouter: () => ({ push: nav.push, replace: nav.replace }),
  redirect: vi.fn(),
}));

