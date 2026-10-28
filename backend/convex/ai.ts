// AI question generation on QuillFin's own Anthropic key, within the
// user's plan allowance. Users who bring their own key call their provider
// directly from the app and never come through here.
import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import { action } from "./_generated/server";
import {
  buildQuestionGenerationPrompt,
  GenerationParseError,
  parseGeneratedQuestions,
  type GeneratedQuestion,
} from "./aiPrompts";
import { AI_LIMITS } from "./plans";
import { requireIdentity } from "./users";

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const DEFAULT_MODEL = "claude-sonnet-5-5";
const MAX_TOKENS = 4096;
const TIMEOUT_MS = 60_000;

function aiError(code: string, message: string) {
  return new ConvexError({ code, message });
}

async function callAnthropic(apiKey: string, model: string, system: string, user: string): Promise<string> {
  let response: Response;
  try {
    response = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": ANTHROPIC_VERSION,
        "content-type": "application/json",
      },
      body: JSON.stringify({ model, max_tokens: MAX_TOKENS, system, messages: [{ role: "user", content: user }] }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (e) {
    throw aiError("AI_UNAVAILABLE", `Couldn't reach the AI service: ${e}`);
  }
  if (!response.ok) {
    // The body may echo request details; log it, don't return it.
    console.error(`Anthropic returned HTTP ${response.status}: ${await response.text()}`);
    throw aiError("AI_UNAVAILABLE", `The AI service returned an error (HTTP ${response.status}). Try again shortly.`);
  }
  const body = (await response.json()) as { content?: { type: string; text?: string }[] };
  const text = body.content?.find((block) => block.type === "text")?.text;
  if (text === undefined) throw aiError("AI_BAD_RESPONSE", "The AI service returned an unexpected response.");
  return text;
}

export const generateQuestions = action({
  args: {
    noteText: v.string(),
    numQuestions: v.number(),
    questionFormat: v.union(v.literal("short_answer"), v.literal("multiple_choice")),
    linkedNotes: v.optional(
      v.array(v.object({ title: v.string(), excerpt: v.string(), sharedKeywords: v.array(v.string()) })),
    ),
  },
  handler: async (
    ctx,
    args,
  ): Promise<{ questions: GeneratedQuestion[]; usage: { period: string; used: number; limit: number } }> => {
    const identity = await requireIdentity(ctx);
    const noteText = args.noteText.trim();
    if (noteText.length === 0) throw aiError("INVALID_REQUEST", "The note is empty.");
    if (noteText.length > AI_LIMITS.maxNoteChars) {
      throw aiError(
        "INVALID_REQUEST",
        `Notes over ${AI_LIMITS.maxNoteChars.toLocaleString("en-US")} characters can't be sent for generation.`,
      );
    }
    if (!Number.isInteger(args.numQuestions) || args.numQuestions < 1 || args.numQuestions > AI_LIMITS.maxQuestionsPerRequest) {
      throw aiError("INVALID_REQUEST", `Ask for between 1 and ${AI_LIMITS.maxQuestionsPerRequest} questions.`);
    }
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw aiError("AI_NOT_CONFIGURED", "AI generation isn't set up on this server yet.");

    const usage = await ctx.runMutation(internal.billing.reserveAiNote, { clerkId: identity.subject });
    try {
      const prompt = buildQuestionGenerationPrompt(
        noteText,
        args.numQuestions,
        args.questionFormat,
        args.linkedNotes?.slice(0, AI_LIMITS.maxLinkedNotes),
      );
      const text = await callAnthropic(apiKey, process.env.QUILLFIN_AI_MODEL || DEFAULT_MODEL, prompt.system, prompt.user);
      let questions: GeneratedQuestion[];
      try {
        questions = parseGeneratedQuestions(text);
      } catch (e) {
        throw aiError("AI_BAD_RESPONSE", (e as GenerationParseError).message);
      }
      return { questions, usage };
    } catch (e) {
      // A failed generation doesn't count against the allowance.
      await ctx.runMutation(internal.billing.refundAiNote, { clerkId: identity.subject, period: usage.period });
      throw e;
    }
  },
});
