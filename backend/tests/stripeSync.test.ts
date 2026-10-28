import type Stripe from "stripe";
import { describe, expect, test } from "vitest";
import { subscriptionIdOf, subscriptionRecord } from "../convex/stripeSync";

const event = (type: string, object: Record<string, unknown>) => ({ type, data: { object } }) as unknown as Stripe.Event;

describe("subscriptionIdOf", () => {
  test("reads the id from subscription events", () => {
    expect(subscriptionIdOf(event("customer.subscription.updated", { object: "subscription", id: "sub_1" }))).toBe("sub_1");
  });

  test("reads the subscription from a completed checkout, as an id or expanded", () => {
    const session = (subscription: unknown) =>
      event("checkout.session.completed", { object: "checkout.session", id: "cs_1", subscription });
    expect(subscriptionIdOf(session("sub_1"))).toBe("sub_1");
    expect(subscriptionIdOf(session({ id: "sub_2" }))).toBe("sub_2");
    expect(subscriptionIdOf(session(null))).toBeNull();
  });

  test("ignores other events", () => {
    expect(subscriptionIdOf(event("invoice.paid", { object: "invoice", id: "in_1", subscription: "sub_1" }))).toBeNull();
    expect(subscriptionIdOf(event("customer.subscription.updated", { object: "invoice", id: "in_1" }))).toBeNull();
  });
});

describe("subscriptionRecord", () => {
  const subscription = (overrides: Record<string, unknown> = {}) =>
    ({
      id: "sub_1",
      customer: "cus_1",
      status: "active",
      cancel_at_period_end: false,
      metadata: { userId: "u1" },
      items: { data: [{ price: { id: "price_year", recurring: { interval: "year" } }, current_period_end: 1_900_000_000 }] },
      ...overrides,
    }) as unknown as Stripe.Subscription;

  test("maps Stripe's fields, converting seconds to milliseconds", () => {
    expect(subscriptionRecord(subscription())).toEqual({
      stripeSubscriptionId: "sub_1",
      stripeCustomerId: "cus_1",
      userId: "u1",
      status: "active",
      priceId: "price_year",
      interval: "year",
      currentPeriodEnd: 1_900_000_000_000,
      cancelAtPeriodEnd: false,
    });
  });

  test("handles an expanded customer, no metadata and no items", () => {
    const record = subscriptionRecord(subscription({ customer: { id: "cus_2" }, metadata: {}, items: { data: [] } }));
    expect(record).toMatchObject({ stripeCustomerId: "cus_2", userId: undefined, priceId: undefined, currentPeriodEnd: undefined });
  });
});
