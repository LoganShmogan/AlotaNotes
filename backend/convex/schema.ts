import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import { syncedTables } from "./validators";

// Every synced table has the same envelope around its `data`:
//   uid        the client-generated UUID, unique per user
//   updatedAt  last-writer-wins clock (ms), as sent by the client
//   deletedAt  set on a tombstone, whose `data` is dropped
//   seq        the user's sync counter when the row last changed; pull
//              returns rows with seq > the client's cursor
const synced = <T extends (typeof syncedTables)[keyof typeof syncedTables]>(data: T) =>
  defineTable({
    userId: v.id("users"),
    uid: v.string(),
    updatedAt: v.number(),
    deletedAt: v.optional(v.number()),
    seq: v.number(),
    data: v.optional(data),
  })
    .index("by_user_uid", ["userId", "uid"])
    .index("by_user_seq", ["userId", "seq"]);

export default defineSchema({
  users: defineTable({
    // The Clerk user id (the JWT `subject`), the same from web and app.
    clerkId: v.string(),
    email: v.optional(v.string()),
    name: v.optional(v.string()),
    // Bumped once per changed row; the last value handed out.
    syncSeq: v.number(),
    // Live rows per synced table, for the row limit.
    rowCounts: v.record(v.string(), v.number()),
    stripeCustomerId: v.optional(v.string()),
  })
    .index("by_clerk_id", ["clerkId"])
    .index("by_stripe_customer", ["stripeCustomerId"]),

  // The extra indexes serve the web app, which reads Convex directly: rows
  // by parent (and for deleting a parent's children), and by date.
  folders: synced(syncedTables.folders).index("by_parent", ["userId", "data.parentFolderUid"]),
  notes: synced(syncedTables.notes).index("by_folder", ["userId", "data.folderUid"]),
  questions: synced(syncedTables.questions)
    .index("by_note", ["userId", "data.noteUid"])
    .index("by_due", ["userId", "data.nextDueAt"]),
  questionChoices: synced(syncedTables.questionChoices).index("by_question", ["userId", "data.questionUid"]),
  questionHistory: synced(syncedTables.questionHistory)
    .index("by_question", ["userId", "data.questionUid"])
    .index("by_asked", ["userId", "data.askedAt"]),
  problems: synced(syncedTables.problems).index("by_due", ["userId", "data.nextDueAt"]),
  problemAttempts: synced(syncedTables.problemAttempts)
    .index("by_problem", ["userId", "data.problemUid"])
    .index("by_attempted", ["userId", "data.attemptedAt"]),

  // Written only by the Stripe webhook, from Stripe's own copy of the
  // subscription, so it is never ahead of or behind Stripe for long.
  subscriptions: defineTable({
    userId: v.id("users"),
    stripeSubscriptionId: v.string(),
    stripeCustomerId: v.string(),
    status: v.string(),
    priceId: v.optional(v.string()),
    interval: v.optional(v.string()),
    currentPeriodEnd: v.optional(v.number()),
    cancelAtPeriodEnd: v.boolean(),
  })
    .index("by_user", ["userId"])
    .index("by_stripe_id", ["stripeSubscriptionId"]),

  // AI generations on QuillFin's key, per user per UTC month.
  usage: defineTable({
    userId: v.id("users"),
    period: v.string(),
    aiNotes: v.number(),
  }).index("by_user_period", ["userId", "period"]),
});
