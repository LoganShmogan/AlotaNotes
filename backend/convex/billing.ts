// Entitlements and usage. The plan is always derived from the
// `subscriptions` table (written by the Stripe webhook), never from
// anything a client sends.
import { ConvexError, v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import { internalMutation, query, type QueryCtx } from "./_generated/server";
import { isProStatus, PLANS, usagePeriod, type PlanId } from "./plans";
import { findUser, getOrCreateUser, requireIdentity } from "./users";

async function activeSubscription(ctx: QueryCtx, userId: Id<"users">): Promise<Doc<"subscriptions"> | null> {
  const subscriptions = await ctx.db
    .query("subscriptions")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .collect();
  return subscriptions.find((s) => isProStatus(s.status)) ?? null;
}

export async function planFor(ctx: QueryCtx, userId: Id<"users">): Promise<PlanId> {
  return (await activeSubscription(ctx, userId)) === null ? "free" : "pro";
}

async function usageRow(ctx: QueryCtx, userId: Id<"users">, period: string) {
  return ctx.db
    .query("usage")
    .withIndex("by_user_period", (q) => q.eq("userId", userId).eq("period", period))
    .unique();
}

// Everything Settings > Plan shows.
export const me = query({
  args: {},
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const period = usagePeriod(Date.now());
    const user = await findUser(ctx, identity.subject);
    const subscription = user === null ? null : await activeSubscription(ctx, user._id);
    const plan: PlanId = subscription === null ? "free" : "pro";
    const used = user === null ? 0 : ((await usageRow(ctx, user._id, period))?.aiNotes ?? 0);
    return {
      plan,
      planName: PLANS[plan].name,
      aiNotes: { period, used, limit: PLANS[plan].aiNotesPerMonth },
      subscription:
        subscription === null
          ? null
          : {
              status: subscription.status,
              interval: subscription.interval ?? null,
              currentPeriodEnd: subscription.currentPeriodEnd ?? null,
              cancelAtPeriodEnd: subscription.cancelAtPeriodEnd,
            },
      // False until the Stripe prices are configured (Docs/setup_guide.md).
      upgradeAvailable: Boolean(process.env.STRIPE_PRICE_PRO_MONTHLY || process.env.STRIPE_PRICE_PRO_YEARLY),
    };
  },
});

// Takes one AI generation from this month's allowance before the model is
// called, so concurrent requests can't overshoot it. `refundAiNote` gives
// it back if the call then fails.
export const reserveAiNote = internalMutation({
  args: { clerkId: v.string() },
  handler: async (ctx, { clerkId }) => {
    const user = await getOrCreateUser(ctx, clerkId);
    const plan = await planFor(ctx, user._id);
    const limit = PLANS[plan].aiNotesPerMonth;
    const period = usagePeriod(Date.now());
    const row = await usageRow(ctx, user._id, period);
    const used = row?.aiNotes ?? 0;
    if (used >= limit) {
      throw new ConvexError({
        code: "AI_LIMIT_REACHED",
        message:
          plan === "free"
            ? `You've used all ${limit} AI generations this month. Upgrade to Pro, or add your own API key in Settings.`
            : `You've used all ${limit} AI generations this month. They reset on the 1st.`,
        plan,
        limit,
        period,
      });
    }
    if (row === null) {
      await ctx.db.insert("usage", { userId: user._id, period, aiNotes: 1 });
    } else {
      await ctx.db.patch(row._id, { aiNotes: used + 1 });
    }
    return { period, used: used + 1, limit };
  },
});

export const refundAiNote = internalMutation({
  args: { clerkId: v.string(), period: v.string() },
  handler: async (ctx, { clerkId, period }) => {
    const user = await findUser(ctx, clerkId);
    if (user === null) return;
    const row = await usageRow(ctx, user._id, period);
    if (row !== null && row.aiNotes > 0) await ctx.db.patch(row._id, { aiNotes: row.aiNotes - 1 });
  },
});

// --- Stripe bookkeeping, used by stripeActions.ts ---

export const stripeAccount = internalMutation({
  args: { clerkId: v.string(), email: v.optional(v.string()) },
  handler: async (ctx, { clerkId, email }) => {
    const user = await getOrCreateUser(ctx, clerkId, email ? { email } : {});
    return {
      userId: user._id,
      email: user.email,
      stripeCustomerId: user.stripeCustomerId,
      plan: await planFor(ctx, user._id),
    };
  },
});

export const setStripeCustomer = internalMutation({
  args: { userId: v.id("users"), stripeCustomerId: v.string() },
  handler: async (ctx, { userId, stripeCustomerId }) => {
    await ctx.db.patch(userId, { stripeCustomerId });
  },
});

// Writes Stripe's current copy of a subscription. The webhook always
// re-reads the subscription from Stripe before calling this, so events
// arriving out of order still leave the latest state.
export const upsertSubscription = internalMutation({
  args: {
    stripeSubscriptionId: v.string(),
    stripeCustomerId: v.string(),
    // From the subscription's metadata, set at checkout.
    userId: v.optional(v.string()),
    status: v.string(),
    priceId: v.optional(v.string()),
    interval: v.optional(v.string()),
    currentPeriodEnd: v.optional(v.number()),
    cancelAtPeriodEnd: v.boolean(),
  },
  handler: async (ctx, { userId: metadataUserId, ...fields }) => {
    let userId = metadataUserId ? ctx.db.normalizeId("users", metadataUserId) : null;
    if (userId === null) {
      const user = await ctx.db
        .query("users")
        .withIndex("by_stripe_customer", (q) => q.eq("stripeCustomerId", fields.stripeCustomerId))
        .unique();
      userId = user?._id ?? null;
    }
    if (userId === null) {
      // Not one of ours (e.g. made by hand in the Stripe dashboard).
      console.warn(`No user for Stripe customer ${fields.stripeCustomerId}; ignoring.`);
      return { stored: false };
    }
    const existing = await ctx.db
      .query("subscriptions")
      .withIndex("by_stripe_id", (q) => q.eq("stripeSubscriptionId", fields.stripeSubscriptionId))
      .unique();
    if (existing === null) {
      await ctx.db.insert("subscriptions", { userId, ...fields });
    } else {
      await ctx.db.replace(existing._id, { userId, ...fields });
    }
    return { stored: true };
  },
});
