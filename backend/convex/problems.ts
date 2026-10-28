// The practice-problem tracker, for the web app.
import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { allLive, checkRetention, invalid, liveChildren, notFound, nowIso, requireText } from "./library";
import { callerUser, getRow, newUid, RowWriter } from "./rows";
import { cardFromRow, cardToRow, newCard, reviewCard, type Rating } from "./scheduling";

const difficulty = v.union(v.literal("easy"), v.literal("medium"), v.literal("hard"));
const fields = {
  title: v.string(),
  difficulty,
  url: v.optional(v.union(v.string(), v.null())),
  platform: v.optional(v.string()),
  tags: v.optional(v.array(v.string())),
  solution: v.optional(v.string()),
  notes: v.optional(v.string()),
};

/// Trimmed, lower-case, de-duplicated, as the app stores them (comma-joined).
export function normalizeTags(tags: string[]): string {
  return [...new Set(tags.map((t) => t.trim().toLowerCase()).filter((t) => t.length > 0))].join(",");
}

// Attempts by time, then by when they were stored (two can share a millisecond).
const byAttemptOrder = (
  a: { _creationTime: number; data: { attemptedAt: string } },
  b: { _creationTime: number; data: { attemptedAt: string } },
) => a.data.attemptedAt.localeCompare(b.data.attemptedAt) || a._creationTime - b._creationTime;

function checkUrl(url: string | null | undefined): string | null {
  const trimmed = url?.trim();
  if (!trimmed) return null;
  if (!/^https?:\/\//i.test(trimmed)) invalid("Links must start with http:// or https://.");
  return trimmed;
}

function summary(p: { uid: string; data: NonNullable<Awaited<ReturnType<typeof getRow<"problems">>>>["data"] & object }) {
  const d = p.data;
  return {
    uid: p.uid,
    title: d.title,
    url: d.url ?? null,
    platform: d.platform,
    difficulty: d.difficulty,
    tags: d.tags === "" ? [] : d.tags.split(","),
    card: cardFromRow(d),
    createdAt: d.createdAt,
    updatedAt: d.updatedAt,
  };
}

export const list = query({
  args: {},
  handler: async (ctx) => {
    const user = await callerUser(ctx);
    if (user === null) return [];
    const problems = await allLive(ctx, "problems", user._id);
    // Oldest first, so the last one seen for a problem is its latest.
    const attempts = (await allLive(ctx, "problemAttempts", user._id)).sort(byAttemptOrder);
    const byProblem = new Map<string, { count: number; solved: boolean }>();
    for (const a of attempts) {
      const s = byProblem.get(a.data.problemUid) ?? { count: 0, solved: false };
      byProblem.set(a.data.problemUid, { count: s.count + 1, solved: a.data.solved });
    }
    return problems
      .map((p) => {
        const s = byProblem.get(p.uid);
        return { ...summary(p), attempts: s?.count ?? 0, lastSolved: s ? s.solved : null };
      })
      .sort((a, b) => a.title.localeCompare(b.title, undefined, { sensitivity: "base" }));
  },
});

export const get = query({
  args: { uid: v.string() },
  handler: async (ctx, { uid }) => {
    const user = await callerUser(ctx);
    if (user === null) return null;
    const problem = await getRow(ctx, "problems", user._id, uid);
    if (problem === null || problem.data === undefined) return null;
    const attempts = await liveChildren(ctx, "problemAttempts", "by_problem", user._id, "data.problemUid", uid);
    return {
      ...summary({ uid, data: problem.data }),
      solution: problem.data.solution,
      notes: problem.data.notes,
      attempts: attempts
        .sort((a, b) => byAttemptOrder(b, a))
        .map((a) => ({
          uid: a.uid,
          attemptedAt: a.data.attemptedAt,
          solved: a.data.solved,
          durationMinutes: a.data.durationMinutes ?? null,
          rating: a.data.rating,
          notes: a.data.notes,
        })),
    };
  },
});

export const create = mutation({
  args: fields,
  handler: async (ctx, args) => {
    const writer = await RowWriter.forCaller(ctx);
    const uid = newUid();
    const at = nowIso(writer.now);
    await writer.put("problems", uid, {
      title: requireText(args.title, "title"),
      url: checkUrl(args.url),
      platform: args.platform?.trim() ?? "",
      difficulty: args.difficulty,
      tags: normalizeTags(args.tags ?? []),
      solution: args.solution ?? "",
      notes: args.notes ?? "",
      // No card until the first attempt, so an untried problem is never due.
      nextDueAt: null,
      createdAt: at,
      updatedAt: at,
    });
    await writer.flush();
    return uid;
  },
});

export const update = mutation({
  args: { uid: v.string(), ...fields },
  handler: async (ctx, { uid, ...args }) => {
    const writer = await RowWriter.forCaller(ctx);
    const problem = await writer.get("problems", uid);
    if (problem === null || problem.data === undefined) notFound("problem");
    await writer.put(
      "problems",
      uid,
      {
        ...problem.data,
        title: requireText(args.title, "title"),
        url: checkUrl(args.url),
        platform: args.platform?.trim() ?? problem.data.platform,
        difficulty: args.difficulty,
        tags: args.tags === undefined ? problem.data.tags : normalizeTags(args.tags),
        solution: args.solution ?? problem.data.solution,
        notes: args.notes ?? problem.data.notes,
        updatedAt: nowIso(writer.now),
      },
      { existing: problem },
    );
    await writer.flush();
  },
});

export const remove = mutation({
  args: { uid: v.string() },
  handler: async (ctx, { uid }) => {
    const writer = await RowWriter.forCaller(ctx);
    await writer.remove("problems", uid);
    await writer.flush();
  },
});

/// Logs an attempt and reschedules the problem (self-rated, as in the app).
export const logAttempt = mutation({
  args: {
    uid: v.string(),
    solved: v.boolean(),
    rating: v.union(v.literal(1), v.literal(2), v.literal(3), v.literal(4)),
    durationMinutes: v.optional(v.union(v.number(), v.null())),
    notes: v.optional(v.string()),
    retention: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const retention = checkRetention(args.retention);
    if (args.durationMinutes != null && !(Number.isInteger(args.durationMinutes) && args.durationMinutes >= 0)) {
      invalid("Time taken must be a whole number of minutes.");
    }
    const writer = await RowWriter.forCaller(ctx);
    const problem = await writer.get("problems", args.uid);
    if (problem === null || problem.data === undefined) notFound("problem");
    const card = reviewCard(cardFromRow(problem.data) ?? newCard(writer.now), args.rating as Rating, writer.now, retention);
    await writer.put("problems", args.uid, { ...problem.data, ...cardToRow(card) }, { existing: problem });
    await writer.put("problemAttempts", newUid(), {
      problemUid: args.uid,
      attemptedAt: nowIso(writer.now),
      solved: args.solved,
      durationMinutes: args.durationMinutes ?? null,
      rating: args.rating,
      notes: args.notes ?? "",
      nextDueAfter: nowIso(card.due),
      stabilityAfter: card.stability,
    });
    await writer.flush();
    return { nextDueAt: nowIso(card.due) };
  },
});
