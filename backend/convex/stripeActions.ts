"use node";
// Stripe Checkout, the Billing Portal and webhook handling. Nothing
// card-related reaches the apps: they open the URL these return.
import { ConvexError, v } from "convex/values";
import Stripe from "stripe";
import { internal } from "./_generated/api";
import { action, internalAction } from "./_generated/server";
import { subscriptionIdOf, subscriptionRecord } from "./stripeSync";
import { requireIdentity } from "./users";

function stripeClient(): Stripe {
  const key = process.env.STRIPE_SECRET_KEY;
  if (!key) throw new ConvexError({ code: "BILLING_NOT_CONFIGURED", message: "Billing isn't set up on this server yet." });
  return new Stripe(key);
}

// Where Stripe sends the browser back to: the web app's plan page, which
// the Flutter app also links to. Fixed server-side so a client can't turn
// Checkout into an open redirect.
function planPageUrl(query: string): string {
  const site = process.env.SITE_URL;
  if (!site) throw new ConvexError({ code: "BILLING_NOT_CONFIGURED", message: "SITE_URL isn't set on this server." });
  return `${site.replace(/\/$/, "")}/settings/plan${query}`;
}

export const createCheckoutSession = action({
  args: { interval: v.union(v.literal("month"), v.literal("year")) },
  handler: async (ctx, { interval }): Promise<{ url: string }> => {
    const identity = await requireIdentity(ctx);
    const price = interval === "month" ? process.env.STRIPE_PRICE_PRO_MONTHLY : process.env.STRIPE_PRICE_PRO_YEARLY;
    if (!price) {
      throw new ConvexError({ code: "BILLING_NOT_CONFIGURED", message: `There's no ${interval}ly Pro price set up yet.` });
    }
    const stripe = stripeClient();
    const account = await ctx.runMutation(internal.billing.stripeAccount, {
      clerkId: identity.subject,
      email: identity.email,
    });
    if (account.plan === "pro") {
      throw new ConvexError({ code: "ALREADY_PRO", message: "You're already on Pro. Manage your plan from Settings." });
    }

    let customerId = account.stripeCustomerId;
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: account.email,
        metadata: { userId: account.userId, clerkId: identity.subject },
      });
      customerId = customer.id;
      await ctx.runMutation(internal.billing.setStripeCustomer, { userId: account.userId, stripeCustomerId: customerId });
    }

    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      customer: customerId,
      client_reference_id: account.userId,
      line_items: [{ price, quantity: 1 }],
      subscription_data: { metadata: { userId: account.userId } },
      allow_promotion_codes: true,
      success_url: planPageUrl("?checkout=success"),
      cancel_url: planPageUrl("?checkout=cancelled"),
    });
    return { url: session.url! };
  },
});

export const createPortalSession = action({
  args: {},
  handler: async (ctx): Promise<{ url: string }> => {
    const identity = await requireIdentity(ctx);
    const stripe = stripeClient();
    const account = await ctx.runMutation(internal.billing.stripeAccount, { clerkId: identity.subject });
    if (!account.stripeCustomerId) {
      throw new ConvexError({ code: "NO_BILLING_ACCOUNT", message: "You don't have a subscription to manage yet." });
    }
    const session = await stripe.billingPortal.sessions.create({
      customer: account.stripeCustomerId,
      return_url: planPageUrl(""),
    });
    return { url: session.url };
  },
});

// Called by the /stripe/webhook HTTP action with the raw body. Throwing
// (a bad signature, or Stripe unreachable) makes http.ts answer 400, and
// Stripe retries with backoff. Handling is idempotent, so retries are safe.
export const handleWebhook = internalAction({
  args: { body: v.string(), signature: v.string() },
  handler: async (ctx, { body, signature }) => {
    const secret = process.env.STRIPE_WEBHOOK_SECRET;
    if (!secret) throw new Error("STRIPE_WEBHOOK_SECRET isn't set.");
    const stripe = stripeClient();
    const event = stripe.webhooks.constructEvent(body, signature, secret);
    const subscriptionId = subscriptionIdOf(event);
    if (subscriptionId === null) return;
    // Always store Stripe's current copy, not the event's snapshot, so
    // events arriving out of order can't leave a stale status behind.
    const subscription = await stripe.subscriptions.retrieve(subscriptionId);
    await ctx.runMutation(internal.billing.upsertSubscription, subscriptionRecord(subscription));
  },
});
