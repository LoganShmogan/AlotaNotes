import { describe, expect, test } from "vitest";
import { api } from "../convex/_generated/api";
import { as, expectCode, newTest } from "./setup";

describe("users", () => {
  test("me is null until the user's first mutation", async () => {
    expect(await as(newTest(), "user_alice").query(api.users.me, {})).toBeNull();
  });

  test("ensure creates the user from the Clerk identity and keeps the profile current", async () => {
    const t = newTest();
    await as(t, "user_alice", { email: "a@example.com", name: "Alice" }).mutation(api.users.ensure, {});
    const me = await as(t, "user_alice").query(api.users.me, {});
    expect(me).toMatchObject({ clerkId: "user_alice", email: "a@example.com", name: "Alice", rowCounts: {} });
    expect(me?.limits.maxNoteBytes).toBeGreaterThan(0);

    await as(t, "user_alice", { email: "new@example.com", name: "Alice" }).mutation(api.users.ensure, {});
    expect((await as(t, "user_alice").query(api.users.me, {}))?.email).toBe("new@example.com");
    expect(await t.run((ctx) => ctx.db.query("users").collect())).toHaveLength(1);
  });

  test("ensure needs a signed-in user", async () => {
    await expectCode(newTest().mutation(api.users.ensure, {}), "UNAUTHENTICATED");
  });
});
