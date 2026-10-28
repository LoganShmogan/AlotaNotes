import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "../convex/_generated/api";
import { as, expectCode, newTest } from "./setup";

// A stand-in for the Stripe SDK: each method is a mock the tests program.
const stripe = vi.hoisted(() => ({
  customersCreate: vi.fn(),
  checkoutCreate: vi.fn(),
  portalCreate: vi.fn(),
  subscriptionsRetrieve: vi.fn(),
  constructEvent: vi.fn(),
  constructedWith: [] as string[],
}));

vi.mock("stripe", () => ({
  default: class {
    customers = { create: stripe.customersCreate };
    checkout = { sessions: { create: stripe.checkoutCreate } };
    billingPortal = { sessions: { create: stripe.portalCreate } };
    subscriptions = { retrieve: stripe.subscriptionsRetrieve };
    webhooks = { constructEvent: stripe.constructEvent };
    constructor(key: string) {
      stripe.constructedWith.push(key);
    }
  },
}));

const ENV = {
  STRIPE_SECRET_KEY: "sk_test_1",
  STRIPE_WEBHOOK_SECRET: "whsec_1",
  STRIPE_PRICE_PRO_MONTHLY: "price_month",
  STRIPE_PRICE_PRO_YEARLY: "price_year",
  SITE_URL: "https://quillfin.test/",
};

const stripeSubscription = (status = "active") => ({
  id: "sub_1",
  customer: "cus_1",
  status,
  cancel_at_period_end: false,
  metadata: {},
  items: { data: [{ price: { id: "price_month", recurring: { interval: "month" } }, current_period_end: 1_900_000_000 }] },
});

beforeEach(() => {
  Object.assign(process.env, ENV);
  vi.clearAllMocks();
  stripe.constructedWith.length = 0;
  stripe.customersCreate.mockResolvedValue({ id: "cus_1" });
  stripe.checkoutCreate.mockResolvedValue({ url: "https://checkout.stripe.test/s1" });
  stripe.portalCreate.mockResolvedValue({ url: "https://billing.stripe.test/p1" });
  stripe.subscriptionsRetrieve.mockResolvedValue(stripeSubscription());
});

afterEach(() => {
  for (const key of Object.keys(ENV)) delete process.env[key];
});

async function stripeCustomerOf(t: ReturnType<typeof newTest>) {
  return t.run(async (ctx) => (await ctx.db.query("users").first())?.stripeCustomerId);
}

describe("createCheckoutSession", () => {
  test("creates a customer once and a subscription Checkout for the chosen price", async () => {
    const t = newTest();
    const alice = as(t, "user_alice", { email: "a@example.com" });
    expect(await alice.action(api.stripeActions.createCheckoutSession, { interval: "month" })).toEqual({
      url: "https://checkout.stripe.test/s1",
    });
    expect(stripe.constructedWith).toEqual(["sk_test_1"]);
    expect(stripe.customersCreate).toHaveBeenCalledWith({
      email: "a@example.com",
      metadata: { userId: expect.any(String), clerkId: "user_alice" },
    });
    expect(await stripeCustomerOf(t)).toBe("cus_1");

    const session = stripe.checkoutCreate.mock.calls[0][0];
    expect(session).toMatchObject({
      mode: "subscription",
      customer: "cus_1",
      line_items: [{ price: "price_month", quantity: 1 }],
      success_url: "https://quillfin.test/settings/plan?checkout=success",
      cancel_url: "https://quillfin.test/settings/plan?checkout=cancelled",
    });
    expect(session.subscription_data.metadata.userId).toBe(session.client_reference_id);

    await alice.action(api.stripeActions.createCheckoutSession, { interval: "year" });
    expect(stripe.customersCreate).toHaveBeenCalledTimes(1);
    expect(stripe.checkoutCreate.mock.calls[1][0].line_items[0].price).toBe("price_year");
  });

  test("refuses users who are already Pro", async () => {
    const t = newTest();
    await as(t, "user_alice").action(api.stripeActions.createCheckoutSession, { interval: "month" });
    await t.mutation(internal.billing.upsertSubscription, {
      stripeSubscriptionId: "sub_1",
      stripeCustomerId: "cus_1",
      status: "active",
      cancelAtPeriodEnd: false,
    });
    await expectCode(as(t, "user_alice").action(api.stripeActions.createCheckoutSession, { interval: "month" }), "ALREADY_PRO");
  });

  test("reports missing configuration", async () => {
    const alice = as(newTest(), "user_alice");
    delete process.env.STRIPE_PRICE_PRO_YEARLY;
    await expectCode(alice.action(api.stripeActions.createCheckoutSession, { interval: "year" }), "BILLING_NOT_CONFIGURED");
    delete process.env.SITE_URL;
    await expectCode(alice.action(api.stripeActions.createCheckoutSession, { interval: "month" }), "BILLING_NOT_CONFIGURED");
    delete process.env.STRIPE_SECRET_KEY;
    await expectCode(alice.action(api.stripeActions.createCheckoutSession, { interval: "month" }), "BILLING_NOT_CONFIGURED");
  });

  test("needs a signed-in user", async () => {
    await expectCode(newTest().action(api.stripeActions.createCheckoutSession, { interval: "month" }), "UNAUTHENTICATED");
  });
});

describe("createPortalSession", () => {
  test("opens the portal for the user's Stripe customer", async () => {
    const t = newTest();
    const alice = as(t, "user_alice");
    await alice.action(api.stripeActions.createCheckoutSession, { interval: "month" });
    expect(await alice.action(api.stripeActions.createPortalSession, {})).toEqual({ url: "https://billing.stripe.test/p1" });
    expect(stripe.portalCreate).toHaveBeenCalledWith({ customer: "cus_1", return_url: "https://quillfin.test/settings/plan" });
  });

  test("refuses users who never started a checkout", async () => {
    await expectCode(as(newTest(), "user_alice").action(api.stripeActions.createPortalSession, {}), "NO_BILLING_ACCOUNT");
  });
});

describe("POST /stripe/webhook", () => {
  const post = (t: ReturnType<typeof newTest>, headers: Record<string, string> = { "stripe-signature": "sig" }) =>
    t.fetch("/stripe/webhook", { method: "POST", body: '{"id":"evt_1"}', headers });

  async function userWithCustomer(t: ReturnType<typeof newTest>) {
    await as(t, "user_alice").action(api.stripeActions.createCheckoutSession, { interval: "month" });
  }

  test("verifies the signature and stores Stripe's current copy of the subscription", async () => {
    const t = newTest();
    await userWithCustomer(t);
    stripe.constructEvent.mockReturnValue({
      type: "customer.subscription.updated",
      data: { object: { object: "subscription", id: "sub_1", status: "incomplete" } },
    });

    expect((await post(t)).status).toBe(200);
    expect(stripe.constructEvent).toHaveBeenCalledWith('{"id":"evt_1"}', "sig", "whsec_1");
    expect(stripe.subscriptionsRetrieve).toHaveBeenCalledWith("sub_1");
    expect((await as(t, "user_alice").query(api.billing.me, {})).plan).toBe("pro");
  });

  test("ignores events that aren't about a subscription", async () => {
    const t = newTest();
    stripe.constructEvent.mockReturnValue({ type: "invoice.paid", data: { object: { object: "invoice", id: "in_1" } } });
    expect((await post(t)).status).toBe(200);
    expect(stripe.subscriptionsRetrieve).not.toHaveBeenCalled();
  });

  test("answers 400 to a bad or missing signature", async () => {
    const t = newTest();
    stripe.constructEvent.mockImplementation(() => {
      throw new Error("No signatures found matching the expected signature");
    });
    expect((await post(t)).status).toBe(400);
    expect((await post(t, {})).status).toBe(400);
    expect(await t.run((ctx) => ctx.db.query("subscriptions").collect())).toEqual([]);
  });

  test("answers 400 when the webhook secret isn't set", async () => {
    delete process.env.STRIPE_WEBHOOK_SECRET;
    expect((await post(newTest())).status).toBe(400);
    expect(stripe.constructEvent).not.toHaveBeenCalled();
  });
});
