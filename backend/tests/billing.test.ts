import { afterEach, describe, expect, test } from "vitest";
import { api, internal } from "../convex/_generated/api";
import { PLANS, usagePeriod } from "../convex/plans";
import { as, expectCode, newTest } from "./setup";

type Test = ReturnType<typeof newTest>;

async function createUser(t: Test, clerkId: string, stripeCustomerId?: string) {
  await as(t, clerkId).mutation(api.users.ensure, {});
  return t.run(async (ctx) => {
    const user = (await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", clerkId))
      .unique())!;
    if (stripeCustomerId) await ctx.db.patch(user._id, { stripeCustomerId });
    return user._id;
  });
}

const subscription = (overrides: Record<string, unknown> = {}) => ({
  stripeSubscriptionId: "sub_1",
  stripeCustomerId: "cus_1",
  status: "active",
  priceId: "price_month",
  interval: "month",
  currentPeriodEnd: 1_900_000_000_000,
  cancelAtPeriodEnd: false,
  ...overrides,
});

afterEach(() => {
  delete process.env.STRIPE_PRICE_PRO_MONTHLY;
});

describe("billing.me", () => {
  test("a new user is on Free with this month's allowance unused", async () => {
    const me = await as(newTest(), "user_alice").query(api.billing.me, {});
    expect(me).toEqual({
      plan: "free",
      planName: "Free",
      aiNotes: { period: usagePeriod(Date.now()), used: 0, limit: PLANS.free.aiNotesPerMonth },
      subscription: null,
      upgradeAvailable: false,
    });
  });

  test("upgrade is offered once a Pro price is configured", async () => {
    process.env.STRIPE_PRICE_PRO_MONTHLY = "price_month";
    expect((await as(newTest(), "user_alice").query(api.billing.me, {})).upgradeAvailable).toBe(true);
  });

  test("needs a signed-in user", async () => {
    await expectCode(newTest().query(api.billing.me, {}), "UNAUTHENTICATED");
  });
});

describe("subscriptions", () => {
  test("an active subscription, matched by metadata userId, makes the user Pro", async () => {
    const t = newTest();
    const userId = await createUser(t, "user_alice");
    const result = await t.mutation(internal.billing.upsertSubscription, subscription({ userId }));
    expect(result).toEqual({ stored: true });

    const me = await as(t, "user_alice").query(api.billing.me, {});
    expect(me.plan).toBe("pro");
    expect(me.aiNotes.limit).toBe(PLANS.pro.aiNotesPerMonth);
    expect(me.subscription).toEqual({
      status: "active",
      interval: "month",
      currentPeriodEnd: 1_900_000_000_000,
      cancelAtPeriodEnd: false,
    });
  });

  test("without metadata the user is found by Stripe customer id", async () => {
    const t = newTest();
    await createUser(t, "user_alice", "cus_1");
    await t.mutation(internal.billing.upsertSubscription, subscription());
    expect((await as(t, "user_alice").query(api.billing.me, {})).plan).toBe("pro");
  });

  test("a subscription for an unknown customer is ignored", async () => {
    const t = newTest();
    const result = await t.mutation(internal.billing.upsertSubscription, subscription({ userId: "not-an-id" }));
    expect(result).toEqual({ stored: false });
    expect(await t.run((ctx) => ctx.db.query("subscriptions").collect())).toEqual([]);
  });

  test("a later update replaces the stored state, and cancelling drops back to Free", async () => {
    const t = newTest();
    await createUser(t, "user_alice", "cus_1");
    await t.mutation(internal.billing.upsertSubscription, subscription());
    await t.mutation(internal.billing.upsertSubscription, subscription({ status: "past_due" }));
    expect((await as(t, "user_alice").query(api.billing.me, {})).plan).toBe("pro");

    await t.mutation(internal.billing.upsertSubscription, subscription({ status: "canceled" }));
    expect((await as(t, "user_alice").query(api.billing.me, {})).plan).toBe("free");
    expect(await t.run((ctx) => ctx.db.query("subscriptions").collect())).toHaveLength(1);
  });

  test("stripeAccount reports the plan and stored customer", async () => {
    const t = newTest();
    const userId = await createUser(t, "user_alice", "cus_1");
    const account = await t.mutation(internal.billing.stripeAccount, { clerkId: "user_alice" });
    expect(account).toMatchObject({ userId, stripeCustomerId: "cus_1", plan: "free" });

    await t.mutation(internal.billing.setStripeCustomer, { userId, stripeCustomerId: "cus_2" });
    expect((await t.mutation(internal.billing.stripeAccount, { clerkId: "user_alice" })).stripeCustomerId).toBe("cus_2");
  });
});

describe("AI allowance", () => {
  test("reserving counts up to the plan limit, then refuses", async () => {
    const t = newTest();
    for (let i = 1; i <= PLANS.free.aiNotesPerMonth; i++) {
      const usage = await t.mutation(internal.billing.reserveAiNote, { clerkId: "user_alice" });
      expect(usage.used).toBe(i);
    }
    const data = await expectCode(t.mutation(internal.billing.reserveAiNote, { clerkId: "user_alice" }), "AI_LIMIT_REACHED");
    expect(data).toMatchObject({ plan: "free", limit: PLANS.free.aiNotesPerMonth });
    expect((await as(t, "user_alice").query(api.billing.me, {})).aiNotes.used).toBe(PLANS.free.aiNotesPerMonth);
  });

  test("Pro users get the Pro limit", async () => {
    const t = newTest();
    const userId = await createUser(t, "user_alice");
    await t.mutation(internal.billing.upsertSubscription, subscription({ userId }));
    await t.run((ctx) =>
      ctx.db.insert("usage", { userId, period: usagePeriod(Date.now()), aiNotes: PLANS.pro.aiNotesPerMonth }),
    );
    const data = await expectCode(t.mutation(internal.billing.reserveAiNote, { clerkId: "user_alice" }), "AI_LIMIT_REACHED");
    expect(data).toMatchObject({ plan: "pro", limit: PLANS.pro.aiNotesPerMonth });
    expect(data.message).toContain("reset on the 1st");
  });

  test("a refund gives one back, never going below zero", async () => {
    const t = newTest();
    const { period } = await t.mutation(internal.billing.reserveAiNote, { clerkId: "user_alice" });
    await t.mutation(internal.billing.refundAiNote, { clerkId: "user_alice", period });
    await t.mutation(internal.billing.refundAiNote, { clerkId: "user_alice", period });
    await t.mutation(internal.billing.refundAiNote, { clerkId: "user_nobody", period });
    expect((await as(t, "user_alice").query(api.billing.me, {})).aiNotes.used).toBe(0);
  });
});
