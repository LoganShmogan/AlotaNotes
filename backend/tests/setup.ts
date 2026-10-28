import { convexTest } from "convex-test";
import { ConvexError, type Value } from "convex/values";
import { expect } from "vitest";
import schema from "../convex/schema";

export const modules = import.meta.glob("../convex/**/*.ts");

export function newTest() {
  return convexTest(schema, modules);
}

export function as(t: ReturnType<typeof newTest>, clerkId: string, profile: { email?: string; name?: string } = {}) {
  return t.withIdentity({ subject: clerkId, issuer: "https://clerk.test", ...profile });
}

// Asserts that `promise` rejects with a ConvexError carrying `code`.
export async function expectCode(promise: Promise<unknown>, code: string) {
  try {
    await promise;
  } catch (e) {
    expect(e).toBeInstanceOf(ConvexError);
    expect((e as ConvexError<{ code: string }>).data.code).toBe(code);
    return (e as ConvexError<{ [key: string]: Value }>).data;
  }
  throw new Error(`Expected a ConvexError with code ${code}, but nothing was thrown.`);
}
