// Turns Stripe objects into what billing.upsertSubscription stores. Kept
// apart from stripeActions.ts (a Node action file) so it can be unit-tested
// without the Stripe SDK. Only types are imported from it.
import type Stripe from "stripe";

// The events that can change a subscription. Each is handled the same way:
// re-read the subscription from Stripe and store that.
export const SUBSCRIPTION_EVENTS = new Set([
  "checkout.session.completed",
  "customer.subscription.created",
  "customer.subscription.updated",
  "customer.subscription.deleted",
  "customer.subscription.paused",
  "customer.subscription.resumed",
]);

// The subscription an event is about, or null if it isn't about one.
export function subscriptionIdOf(event: Stripe.Event): string | null {
  if (!SUBSCRIPTION_EVENTS.has(event.type)) return null;
  const object = event.data.object as { object: string; id: string; subscription?: string | { id: string } | null };
  if (object.object === "subscription") return object.id;
  if (object.object === "checkout.session" && object.subscription) {
    return typeof object.subscription === "string" ? object.subscription : object.subscription.id;
  }
  return null;
}

export function subscriptionRecord(subscription: Stripe.Subscription) {
  const item = subscription.items.data[0];
  const customer = subscription.customer;
  return {
    stripeSubscriptionId: subscription.id,
    stripeCustomerId: typeof customer === "string" ? customer : customer.id,
    userId: subscription.metadata?.userId || undefined,
    status: subscription.status,
    priceId: item?.price.id,
    interval: item?.price.recurring?.interval,
    // Stripe reports seconds; Convex rows use milliseconds.
    currentPeriodEnd: item?.current_period_end ? item.current_period_end * 1000 : undefined,
    cancelAtPeriodEnd: subscription.cancel_at_period_end,
  };
}
