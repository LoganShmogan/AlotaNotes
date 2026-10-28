// Quiz questions and reviews, for the web app. Answers are graded in the
// browser (grading.ts, shared) so feedback is instant; recording a review
// schedules it here with the same FSRS as the app (scheduling.ts).
import { v } from "convex/values";
import type { Id } from "./_generated/dataModel";
import { mutation, query, type QueryCtx } from "./_generated/server";
import { checkRetention, invalid, liveChildren, notFound, nowIso, requireText } from "./library";
import { callerUser, getRow, newUid, RowWriter, type Row } from "./rows";
import { cardFromRow, cardToRow, newCard, reviewCard, type Rating } from "./scheduling";

const questionType = v.union(v.literal("short_answer"), v.literal("multiple_choice"));
const choicesArg = v.array(v.object({ text: v.string(), isCorrect: v.boolean() }));

async function withChoices(ctx: QueryCtx, userId: Id<"users">, q: Row<"questions"> & { data: NonNullable<Row<"questions">["data"]> }) {
  const choices = await liveChildren(ctx, "questionChoices", "by_question", userId, "data.questionUid", q.uid);
  const { noteUid, questionType, prompt, expectedAnswer, active, isManuallyEdited, createdAt } = q.data;
  return {
    uid: q.uid,
    noteUid,
    questionType,
    prompt,
    expectedAnswer,
    active,
    isManuallyEdited,
    createdAt,
    card: cardFromRow(q.data),
    choices: choices
      .sort((a, b) => a.data.sortOrder - b.data.sortOrder)
      .map((c) => ({ uid: c.uid, text: c.data.choiceText, isCorrect: c.data.isCorrect })),
  };
}

export const listByNote = query({
  args: { noteUid: v.string() },
  handler: async (ctx, { noteUid }) => {
    const user = await callerUser(ctx);
    if (user === null) return [];
    const questions = await liveChildren(ctx, "questions", "by_note", user._id, "data.noteUid", noteUid);
    questions.sort((a, b) => a.data.createdAt.localeCompare(b.data.createdAt));
    return Promise.all(questions.map((q) => withChoices(ctx, user._id, q)));
  },
});

/// Active questions due at [now] (sent by the client, so the result is
/// stable between calls), soonest first, each with its note's title.
export const due = query({
  args: { now: v.string(), limit: v.optional(v.number()) },
  handler: async (ctx, { now, limit }) => {
    const user = await callerUser(ctx);
    if (user === null) return [];
    const rows = await ctx.db
      .query("questions")
      .withIndex("by_due", (q) => q.eq("userId", user._id).lte("data.nextDueAt", now))
      .take(500);
    const due = rows.filter((r) => r.deletedAt === undefined && r.data !== undefined && r.data.active);
    const page = due.slice(0, Math.min(limit ?? 100, 200)) as (Row<"questions"> & { data: NonNullable<Row<"questions">["data"]> })[];
    return Promise.all(
      page.map(async (q) => {
        const note = await getRow(ctx, "notes", user._id, q.data.noteUid);
        return { ...(await withChoices(ctx, user._id, q)), noteTitle: note?.data?.title ?? null };
      }),
    );
  },
});

async function writeChoices(writer: RowWriter, questionUid: string, choices: { text: string; isCorrect: boolean }[]) {
  for (const [i, c] of choices.entries()) {
    await writer.put("questionChoices", newUid(), {
      questionUid,
      choiceText: requireText(c.text, "choice"),
      isCorrect: c.isCorrect,
      sortOrder: i,
    });
  }
}

function checkChoices(choices: { isCorrect: boolean }[] | null | undefined) {
  if (choices && (choices.length < 2 || choices.filter((c) => c.isCorrect).length !== 1)) {
    invalid("A multiple-choice question needs at least two choices and exactly one correct one.");
  }
}

/// Saves questions generated for a note (ai:generateQuestions' output).
export const saveGenerated = mutation({
  args: {
    noteUid: v.string(),
    questions: v.array(
      v.object({
        questionType,
        prompt: v.string(),
        expectedAnswer: v.string(),
        choices: v.union(v.array(v.string()), v.null()),
        correctChoiceIndex: v.union(v.number(), v.null()),
      }),
    ),
  },
  handler: async (ctx, { noteUid, questions }) => {
    if (questions.length > 50) invalid("Save at most 50 questions at a time.");
    const writer = await RowWriter.forCaller(ctx);
    const note = await writer.get("notes", noteUid);
    if (note === null || note.deletedAt !== undefined) notFound("note");
    const uids: string[] = [];
    for (const q of questions) {
      const uid = newUid();
      await writer.put("questions", uid, {
        noteUid,
        questionType: q.questionType,
        prompt: requireText(q.prompt, "question", 2000),
        expectedAnswer: requireText(q.expectedAnswer, "answer", 2000),
        ...cardToRow(newCard(writer.now)),
        createdAt: nowIso(writer.now),
        active: true,
        isManuallyEdited: false,
      });
      if (q.choices) {
        await writeChoices(writer, uid, q.choices.map((text, i) => ({ text, isCorrect: i === q.correctChoiceIndex })));
      }
      uids.push(uid);
    }
    await writer.flush();
    return uids;
  },
});

/// Edits a question's wording (marking it hand-edited) and, if given,
/// replaces its choices.
export const update = mutation({
  args: { uid: v.string(), prompt: v.string(), expectedAnswer: v.string(), choices: v.optional(choicesArg) },
  handler: async (ctx, { uid, prompt, expectedAnswer, choices }) => {
    checkChoices(choices);
    const writer = await RowWriter.forCaller(ctx);
    const question = await writer.get("questions", uid);
    if (question === null || question.data === undefined) notFound("question");
    await writer.put(
      "questions",
      uid,
      {
        ...question.data,
        prompt: requireText(prompt, "question", 2000),
        expectedAnswer: requireText(expectedAnswer, "answer", 2000),
        isManuallyEdited: true,
      },
      { existing: question },
    );
    if (choices) {
      for (const old of await liveChildren(ctx, "questionChoices", "by_question", writer.user._id, "data.questionUid", uid)) {
        await writer.put("questionChoices", old.uid, undefined, { existing: old });
      }
      await writeChoices(writer, uid, choices);
    }
    await writer.flush();
  },
});

export const setActive = mutation({
  args: { uid: v.string(), active: v.boolean() },
  handler: async (ctx, { uid, active }) => {
    const writer = await RowWriter.forCaller(ctx);
    const question = await writer.get("questions", uid);
    if (question === null || question.data === undefined) notFound("question");
    await writer.put("questions", uid, { ...question.data, active }, { existing: question });
    await writer.flush();
  },
});

export const remove = mutation({
  args: { uid: v.string() },
  handler: async (ctx, { uid }) => {
    const writer = await RowWriter.forCaller(ctx);
    await writer.remove("questions", uid);
    await writer.flush();
  },
});

/// Records an answered question: reschedules it with FSRS from the
/// server's clock and adds a history row. Returns the new due time.
export const record = mutation({
  args: {
    questionUid: v.string(),
    givenAnswer: v.string(),
    isCorrect: v.boolean(),
    gradingMethod: v.union(v.literal("exact_match"), v.literal("keyword_match"), v.literal("mcq_exact")),
    rating: v.union(v.literal(1), v.literal(2), v.literal(3), v.literal(4)),
    retention: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const retention = checkRetention(args.retention);
    const writer = await RowWriter.forCaller(ctx);
    const question = await writer.get("questions", args.questionUid);
    if (question === null || question.data === undefined) notFound("question");
    const card = reviewCard(cardFromRow(question.data) ?? newCard(writer.now), args.rating as Rating, writer.now, retention);
    await writer.put("questions", args.questionUid, { ...question.data, ...cardToRow(card) }, { existing: question });
    await writer.put("questionHistory", newUid(), {
      questionUid: args.questionUid,
      askedAt: nowIso(writer.now),
      givenAnswer: args.givenAnswer.slice(0, 2000),
      isCorrect: args.isCorrect,
      rating: args.rating,
      gradingMethod: args.gradingMethod,
      nextDueAfter: nowIso(card.due),
      stabilityAfter: card.stability,
    });
    await writer.flush();
    return { nextDueAt: nowIso(card.due) };
  },
});
