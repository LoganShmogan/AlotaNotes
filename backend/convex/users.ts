import { ConvexError, v } from "convex/values";
import type { UserIdentity } from "convex/server";
import type { Doc } from "./_generated/dataModel";
import { mutation, query, type MutationCtx, type QueryCtx } from "./_generated/server";
import { SYNC_LIMITS } from "./plans";

export async function requireIdentity(ctx: { auth: QueryCtx["auth"] }): Promise<UserIdentity> {
  const identity = await ctx.auth.getUserIdentity();
  if (identity === null) {
    throw new ConvexError({ code: "UNAUTHENTICATED", message: "Sign in to continue." });
  }
  return identity;
}

export async function findUser(ctx: QueryCtx, clerkId: string): Promise<Doc<"users"> | null> {
  return ctx.db
    .query("users")
    .withIndex("by_clerk_id", (q) => q.eq("clerkId", clerkId))
    .unique();
}

// Users are created lazily by the first mutation they make, so there's no
// separate sign-up step to forget or to race.
export async function getOrCreateUser(
  ctx: MutationCtx,
  clerkId: string,
  profile: { email?: string; name?: string } = {},
): Promise<Doc<"users">> {
  const existing = await findUser(ctx, clerkId);
  if (existing !== null) return existing;
  const id = await ctx.db.insert("users", { clerkId, syncSeq: 0, rowCounts: {}, ...profile });
  return (await ctx.db.get(id))!;
}

function profileOf(identity: UserIdentity) {
  return {
    ...(identity.email ? { email: identity.email } : {}),
    ...(identity.name ? { name: identity.name } : {}),
  };
}

// Called by both apps right after sign-in: creates the user if needed and
// refreshes the email and name from Clerk.
export const ensure = mutation({
  args: {},
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const profile = profileOf(identity);
    const user = await getOrCreateUser(ctx, identity.subject, profile);
    if (profile.email !== user.email || profile.name !== user.name) {
      await ctx.db.patch(user._id, profile);
    }
    return null;
  },
});

// The signed-in user's sync summary, for Settings > Sync. Null before the
// user's first mutation.
export const me = query({
  args: {},
  returns: v.union(
    v.null(),
    v.object({
      clerkId: v.string(),
      email: v.optional(v.string()),
      name: v.optional(v.string()),
      rowCounts: v.record(v.string(), v.number()),
      limits: v.object({ maxNoteBytes: v.number(), maxRowsPerTable: v.number() }),
    }),
  ),
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const user = await findUser(ctx, identity.subject);
    if (user === null) return null;
    return {
      clerkId: user.clerkId,
      email: user.email,
      name: user.name,
      rowCounts: user.rowCounts,
      limits: { maxNoteBytes: SYNC_LIMITS.maxNoteBytes, maxRowsPerTable: SYNC_LIMITS.maxRowsPerTable },
    };
  },
});
