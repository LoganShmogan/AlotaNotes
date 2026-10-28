import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "../convex/_generated/api";
import { as, expectCode, newTest } from "./setup";

const args = { noteText: "Mitochondria make ATP.", numQuestions: 2, questionFormat: "short_answer" as const };

function anthropicReplies(...responses: Response[]) {
  const fetchMock = vi.fn();
  for (const response of responses) fetchMock.mockResolvedValueOnce(response);
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

const textReply = (text: string) => Response.json({ content: [{ type: "text", text }] });
const goodReply = () =>
  textReply(JSON.stringify({ questions: [{ prompt: "What makes ATP?", expected_answer: "Mitochondria" }] }));

async function used(t: ReturnType<typeof newTest>) {
  return (await as(t, "user_alice").query(api.billing.me, {})).aiNotes.used;
}

beforeEach(() => {
  process.env.ANTHROPIC_API_KEY = "sk-test";
});

afterEach(() => {
  vi.unstubAllGlobals();
  delete process.env.ANTHROPIC_API_KEY;
  delete process.env.QUILLFIN_AI_MODEL;
});

describe("ai.generateQuestions", () => {
  test("returns parsed questions and counts one generation", async () => {
    const t = newTest();
    const fetchMock = anthropicReplies(goodReply());
    const result = await as(t, "user_alice").action(api.ai.generateQuestions, args);

    expect(result.questions).toEqual([
      { questionType: "short_answer", prompt: "What makes ATP?", expectedAnswer: "Mitochondria", choices: null, correctChoiceIndex: null },
    ]);
    expect(result.usage.used).toBe(1);
    expect(await used(t)).toBe(1);

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("https://api.anthropic.com/v1/messages");
    expect(init.headers["x-api-key"]).toBe("sk-test");
    const body = JSON.parse(init.body);
    expect(body.model).toBe("claude-sonnet-5-5");
    expect(body.messages[0].content).toContain("Mitochondria make ATP.");
  });

  test("the model can be changed with QUILLFIN_AI_MODEL", async () => {
    process.env.QUILLFIN_AI_MODEL = "claude-haiku-5-5";
    const fetchMock = anthropicReplies(goodReply());
    await as(newTest(), "user_alice").action(api.ai.generateQuestions, args);
    expect(JSON.parse(fetchMock.mock.calls[0][1].body).model).toBe("claude-haiku-5-5");
  });

  test("an HTTP error from Anthropic is reported and refunded", async () => {
    const t = newTest();
    anthropicReplies(new Response("overloaded", { status: 529 }));
    await expectCode(as(t, "user_alice").action(api.ai.generateQuestions, args), "AI_UNAVAILABLE");
    expect(await used(t)).toBe(0);
  });

  test("a network failure is reported and refunded", async () => {
    const t = newTest();
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("fetch failed")));
    await expectCode(as(t, "user_alice").action(api.ai.generateQuestions, args), "AI_UNAVAILABLE");
    expect(await used(t)).toBe(0);
  });

  test("an unparseable or empty reply is reported and refunded", async () => {
    const t = newTest();
    anthropicReplies(textReply("Sure! Here are some questions."), Response.json({ content: [] }));
    await expectCode(as(t, "user_alice").action(api.ai.generateQuestions, args), "AI_BAD_RESPONSE");
    await expectCode(as(t, "user_alice").action(api.ai.generateQuestions, args), "AI_BAD_RESPONSE");
    expect(await used(t)).toBe(0);
  });

  test("bad requests are refused before the allowance or the model is touched", async () => {
    const t = newTest();
    const fetchMock = anthropicReplies();
    const alice = as(t, "user_alice");
    await expectCode(alice.action(api.ai.generateQuestions, { ...args, noteText: "   " }), "INVALID_REQUEST");
    await expectCode(alice.action(api.ai.generateQuestions, { ...args, noteText: "x".repeat(60_001) }), "INVALID_REQUEST");
    await expectCode(alice.action(api.ai.generateQuestions, { ...args, numQuestions: 0 }), "INVALID_REQUEST");
    await expectCode(alice.action(api.ai.generateQuestions, { ...args, numQuestions: 21 }), "INVALID_REQUEST");
    await expectCode(alice.action(api.ai.generateQuestions, { ...args, numQuestions: 2.5 }), "INVALID_REQUEST");
    expect(fetchMock).not.toHaveBeenCalled();
    expect(await used(t)).toBe(0);
  });

  test("without a server key, generation is unavailable", async () => {
    delete process.env.ANTHROPIC_API_KEY;
    await expectCode(as(newTest(), "user_alice").action(api.ai.generateQuestions, args), "AI_NOT_CONFIGURED");
  });

  test("needs a signed-in user", async () => {
    await expectCode(newTest().action(api.ai.generateQuestions, args), "UNAUTHENTICATED");
  });

  test("stops at the plan limit without calling the model", async () => {
    const t = newTest();
    await t.run(async (ctx) => {
      const userId = await ctx.db.insert("users", { clerkId: "user_alice", syncSeq: 0, rowCounts: {} });
      await ctx.db.insert("usage", { userId, period: new Date().toISOString().slice(0, 7), aiNotes: 20 });
    });
    const fetchMock = anthropicReplies();
    await expectCode(as(t, "user_alice").action(api.ai.generateQuestions, args), "AI_LIMIT_REACHED");
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
