// The Today dashboard, for the web app.
import { v } from "convex/values";
import { query } from "./_generated/server";
import { callerUser } from "./rows";

const FORECAST_DAYS = 7;

/// What's due, what's been done today, and the next week's due times.
/// [now] and [dayStart] (the start of the viewer's local day) come from the
/// client, which knows the time zone.
export const summary = query({
  args: { now: v.string(), dayStart: v.string() },
  handler: async (ctx, { now, dayStart }) => {
    const empty = { dueQuestions: 0, reviewsToday: 0, attemptsToday: 0, problemsDue: [], forecast: [] };
    const user = await callerUser(ctx);
    if (user === null) return empty;
    const horizon = new Date(Date.parse(now) + FORECAST_DAYS * 86_400_000).toISOString();

    const questions = (
      await ctx.db
        .query("questions")
        .withIndex("by_due", (q) => q.eq("userId", user._id).lte("data.nextDueAt", horizon))
        .take(5000)
    ).filter((q) => q.deletedAt === undefined && q.data?.active);
    const problems = (
      await ctx.db
        .query("problems")
        .withIndex("by_due", (q) => q.eq("userId", user._id).gt("data.nextDueAt", "").lte("data.nextDueAt", horizon))
        .take(2000)
    ).filter((p) => p.deletedAt === undefined && p.data !== undefined);

    const reviewsToday = (
      await ctx.db
        .query("questionHistory")
        .withIndex("by_asked", (q) => q.eq("userId", user._id).gte("data.askedAt", dayStart))
        .collect()
    ).filter((h) => h.deletedAt === undefined).length;
    const attemptsToday = (
      await ctx.db
        .query("problemAttempts")
        .withIndex("by_attempted", (q) => q.eq("userId", user._id).gte("data.attemptedAt", dayStart))
        .collect()
    ).filter((a) => a.deletedAt === undefined).length;

    return {
      dueQuestions: questions.filter((q) => q.data!.nextDueAt <= now).length,
      reviewsToday,
      attemptsToday,
      problemsDue: problems
        .filter((p) => p.data!.nextDueAt! <= now)
        .map((p) => ({ uid: p.uid, title: p.data!.title, difficulty: p.data!.difficulty, nextDueAt: p.data!.nextDueAt! })),
      // Due times after now, for the client to bucket by its local days.
      forecast: [
        ...questions.filter((q) => q.data!.nextDueAt > now).map((q) => q.data!.nextDueAt),
        ...problems.filter((p) => p.data!.nextDueAt! > now).map((p) => p.data!.nextDueAt!),
      ].sort(),
    };
  },
});
