import { describe, expect, test, vi } from "vitest";
import { api } from "../convex/_generated/api";
import { SYNC_LIMITS } from "../convex/plans";
import { normalizeTags } from "../convex/problems";
import { as, expectCode, newTest } from "./setup";

type T = ReturnType<typeof newTest>;
const alice = (t: T) => as(t, "user_alice");

async function noteFixture(t: T) {
  const a = alice(t);
  const folderUid = await a.mutation(api.folders.create, { name: "Biology" });
  const noteUid = await a.mutation(api.notes.create, { folderUid, title: "Cells", body: "Mitochondria make ATP." });
  return { a, folderUid, noteUid };
}

const generated = [
  { questionType: "short_answer" as const, prompt: "What makes ATP?", expectedAnswer: "Mitochondria", choices: null, correctChoiceIndex: null },
  { questionType: "multiple_choice" as const, prompt: "Pick one", expectedAnswer: "B", choices: ["A", "B", "C"], correctChoiceIndex: 1 },
];

describe("folders and notes", () => {
  test("create, list, rename and read back, sorted, in the app's row shape", async () => {
    const t = newTest();
    const a = alice(t);
    const bio = await a.mutation(api.folders.create, { name: "  Biology " });
    const sub = await a.mutation(api.folders.create, { name: "cells", parentFolderUid: bio });
    await a.mutation(api.folders.create, { name: "Art" });
    expect(bio).toMatch(/^[0-9a-f]{32}$/);
    expect((await a.query(api.folders.list, {})).map((f) => [f.name, f.parentFolderUid])).toEqual([
      ["Art", null],
      ["Biology", null],
      ["cells", bio],
    ]);

    await a.mutation(api.folders.rename, { uid: sub, name: "Cells" });
    const first = await a.mutation(api.notes.create, { folderUid: sub, title: "One", body: "x".repeat(300) });
    await a.mutation(api.notes.create, { folderUid: sub, title: "Two", body: "" });
    const notes = await a.query(api.notes.listByFolder, { folderUid: sub });
    expect(notes.map((n) => n.title)).toEqual(["One", "Two"]);
    expect(notes[0].preview).toHaveLength(160);

    await a.mutation(api.notes.update, { uid: first, body: "Edited" });
    const note = await a.query(api.notes.get, { uid: first });
    expect(note).toMatchObject({ title: "One", body: "Edited", sortOrder: 0, folderUid: sub, sourceFilename: null });
    expect(note!.updatedAt >= note!.createdAt).toBe(true);
    await a.mutation(api.notes.update, { uid: first, title: "Renamed" });
    expect((await a.query(api.notes.get, { uid: first }))?.body).toBe("Edited");
  });

  test("bad input and missing rows are refused", async () => {
    const t = newTest();
    const { a, folderUid, noteUid } = await noteFixture(t);
    await expectCode(a.mutation(api.folders.create, { name: "  " }), "INVALID_REQUEST");
    await expectCode(a.mutation(api.folders.create, { name: "x".repeat(201) }), "INVALID_REQUEST");
    await expectCode(a.mutation(api.folders.create, { name: "Sub", parentFolderUid: "missing" }), "NOT_FOUND");
    await expectCode(a.mutation(api.folders.rename, { uid: "missing", name: "X" }), "NOT_FOUND");
    await expectCode(a.mutation(api.notes.create, { folderUid: "missing", title: "T", body: "" }), "NOT_FOUND");
    await expectCode(a.mutation(api.notes.update, { uid: "missing", title: "T" }), "NOT_FOUND");
    await expectCode(
      a.mutation(api.notes.create, { folderUid, title: "Huge", body: "x".repeat(SYNC_LIMITS.maxNoteBytes + 1) }),
      "NOTE_TOO_LARGE",
    );
    await expectCode(a.mutation(api.notes.update, { uid: noteUid, body: "x".repeat(SYNC_LIMITS.maxNoteBytes + 1) }), "NOTE_TOO_LARGE");
    expect(await a.query(api.notes.get, { uid: "missing" })).toBeNull();
  });

  test("other users see nothing, and a new user gets empty lists", async () => {
    const t = newTest();
    const { folderUid, noteUid } = await noteFixture(t);
    const bob = as(t, "user_bob");
    expect(await bob.query(api.folders.list, {})).toEqual([]);
    expect(await bob.query(api.notes.listByFolder, { folderUid })).toEqual([]);
    expect(await bob.query(api.notes.get, { uid: noteUid })).toBeNull();
    expect(await bob.query(api.questions.listByNote, { noteUid })).toEqual([]);
    expect(await bob.query(api.problems.list, {})).toEqual([]);
    expect(await bob.query(api.problems.get, { uid: "x" })).toBeNull();
    expect(await bob.query(api.questions.due, { now: new Date().toISOString() })).toEqual([]);
    await expectCode(bob.mutation(api.notes.update, { uid: noteUid, title: "Mine now" }), "NOT_FOUND");
  });

  test("web edits reach the apps' pull, and deleting a folder tombstones everything under it", async () => {
    const t = newTest();
    const { a, folderUid, noteUid } = await noteFixture(t);
    const sub = await a.mutation(api.folders.create, { name: "Sub", parentFolderUid: folderUid });
    await a.mutation(api.notes.create, { folderUid: sub, title: "Deep", body: "" });
    await a.mutation(api.questions.saveGenerated, { noteUid, questions: generated });

    const pulled = await a.query(api.sync.pull, { since: 0 });
    expect(pulled.changes.folders).toHaveLength(2);
    expect(pulled.changes.notes).toHaveLength(2);
    expect(pulled.changes.questions).toHaveLength(2);
    expect(pulled.changes.questionChoices).toHaveLength(3);
    expect((await a.query(api.users.me, {}))?.rowCounts).toMatchObject({ folders: 2, notes: 2, questions: 2, questionChoices: 3 });

    await a.mutation(api.folders.remove, { uid: folderUid });
    await a.mutation(api.folders.remove, { uid: folderUid }); // already gone: no-op
    const after = await a.query(api.sync.pull, { since: pulled.cursor });
    const deleted = Object.values(after.changes).flat();
    expect(deleted).toHaveLength(2 + 2 + 2 + 3);
    expect(deleted.every((r) => r!.deletedAt !== null && r!.data === null)).toBe(true);
    expect(await a.query(api.folders.list, {})).toEqual([]);
    expect((await a.query(api.users.me, {}))?.rowCounts).toMatchObject({ folders: 0, notes: 0, questions: 0, questionChoices: 0 });
  });

  test("deleting a note takes its questions", async () => {
    const t = newTest();
    const { a, folderUid, noteUid } = await noteFixture(t);
    await a.mutation(api.questions.saveGenerated, { noteUid, questions: generated });
    await a.mutation(api.notes.remove, { uid: noteUid });
    expect(await a.query(api.notes.listByFolder, { folderUid })).toEqual([]);
    expect(await a.query(api.questions.listByNote, { noteUid })).toEqual([]);
  });

  test("the web respects the row limit too", async () => {
    const t = newTest();
    const a = alice(t);
    await a.mutation(api.folders.create, { name: "First" });
    await t.run(async (ctx) => {
      const user = (await ctx.db.query("users").first())!;
      await ctx.db.patch(user._id, { rowCounts: { folders: SYNC_LIMITS.maxRowsPerTable } });
    });
    await expectCode(a.mutation(api.folders.create, { name: "One too many" }), "ROW_LIMIT");
  });
});

describe("questions", () => {
  test("generated questions are saved new and due, with their choices", async () => {
    const t = newTest();
    const { a, noteUid } = await noteFixture(t);
    const uids = await a.mutation(api.questions.saveGenerated, { noteUid, questions: generated });
    expect(uids).toHaveLength(2);
    const questions = await a.query(api.questions.listByNote, { noteUid });
    expect(questions.map((q) => q.prompt)).toEqual(["What makes ATP?", "Pick one"]);
    expect(questions[0]).toMatchObject({ choices: [], active: true, isManuallyEdited: false, card: { state: 1, step: 0, stability: null } });
    expect(questions[1].choices.map((c) => [c.text, c.isCorrect])).toEqual([
      ["A", false],
      ["B", true],
      ["C", false],
    ]);

    const due = await a.query(api.questions.due, { now: new Date(Date.now() + 1000).toISOString() });
    expect(due).toHaveLength(2);
    expect(due[0].noteTitle).toBe("Cells");
  });

  test("editing marks it hand-edited and can replace the choices", async () => {
    const t = newTest();
    const { a, noteUid } = await noteFixture(t);
    const [, mcq] = await a.mutation(api.questions.saveGenerated, { noteUid, questions: generated });
    await a.mutation(api.questions.update, {
      uid: mcq,
      prompt: "Pick the right one",
      expectedAnswer: "Y",
      choices: [
        { text: "X", isCorrect: false },
        { text: "Y", isCorrect: true },
      ],
    });
    const q = (await a.query(api.questions.listByNote, { noteUid }))[1];
    expect(q).toMatchObject({ prompt: "Pick the right one", isManuallyEdited: true });
    expect(q.choices.map((c) => c.text)).toEqual(["X", "Y"]);

    await a.mutation(api.questions.update, { uid: mcq, prompt: "Same choices", expectedAnswer: "Y" });
    expect((await a.query(api.questions.listByNote, { noteUid }))[1].choices).toHaveLength(2);

    await expectCode(
      a.mutation(api.questions.update, { uid: mcq, prompt: "P", expectedAnswer: "A", choices: [{ text: "A", isCorrect: true }] }),
      "INVALID_REQUEST",
    );
    await expectCode(a.mutation(api.questions.update, { uid: "missing", prompt: "P", expectedAnswer: "A" }), "NOT_FOUND");
  });

  test("an inactive question isn't due; removing one deletes it", async () => {
    const t = newTest();
    const { a, noteUid } = await noteFixture(t);
    const [first, second] = await a.mutation(api.questions.saveGenerated, { noteUid, questions: generated });
    const later = new Date(Date.now() + 1000).toISOString();
    await a.mutation(api.questions.setActive, { uid: first, active: false });
    expect((await a.query(api.questions.due, { now: later })).map((q) => q.uid)).toEqual([second]);
    await a.mutation(api.questions.remove, { uid: second });
    expect(await a.query(api.questions.due, { now: later })).toEqual([]);
    await expectCode(a.mutation(api.questions.setActive, { uid: "missing", active: true }), "NOT_FOUND");
  });

  test("saving is refused for a missing note or too many questions", async () => {
    const t = newTest();
    const { a } = await noteFixture(t);
    await expectCode(a.mutation(api.questions.saveGenerated, { noteUid: "missing", questions: generated }), "NOT_FOUND");
    await expectCode(
      a.mutation(api.questions.saveGenerated, { noteUid: "x", questions: Array(51).fill(generated[0]) }),
      "INVALID_REQUEST",
    );
  });

  test("recording an answer schedules it with FSRS and adds history the apps pull", async () => {
    vi.useFakeTimers();
    try {
      vi.setSystemTime(Date.UTC(2026, 9, 28, 9));
      const t = newTest();
      const { a, noteUid } = await noteFixture(t);
      const [uid] = await a.mutation(api.questions.saveGenerated, { noteUid, questions: generated });
      const before = await a.query(api.sync.pull, { since: 0 });

      // A new card rated Good goes to the 10-minute learning step.
      const result = await a.mutation(api.questions.record, {
        questionUid: uid,
        givenAnswer: "mitochondria",
        isCorrect: true,
        gradingMethod: "exact_match",
        rating: 3,
      });
      const q = (await a.query(api.questions.listByNote, { noteUid }))[0];
      expect(q.card).toMatchObject({ state: 1, step: 1 });

      const after = await a.query(api.sync.pull, { since: before.cursor });
      const history = after.changes.questionHistory?.[0].data as { askedAt: string };
      expect(history).toMatchObject({ questionUid: uid, givenAnswer: "mitochondria", isCorrect: true, rating: 3 });
      // The fake clock ticks a millisecond per call, so compare to the review time.
      const askedAt = Date.parse(history.askedAt);
      expect(askedAt - Date.UTC(2026, 9, 28, 9)).toBeLessThan(100);
      expect(Date.parse(result.nextDueAt) - askedAt).toBe(10 * 60_000);
      expect(after.changes.questions?.[0].data).toMatchObject({ nextDueAt: result.nextDueAt, fsrsStep: 1 });

      const now = new Date(askedAt + 1).toISOString();
      const today = await a.query(api.today.summary, { now, dayStart: "2026-10-28T00:00:00.000Z" });
      expect(today.reviewsToday).toBe(1);
      expect(today.dueQuestions).toBe(1); // the other question
      expect(today.forecast).toEqual([result.nextDueAt]);

      await expectCode(
        a.mutation(api.questions.record, { questionUid: uid, givenAnswer: "", isCorrect: false, gradingMethod: "exact_match", rating: 1, retention: 2 }),
        "INVALID_REQUEST",
      );
      await expectCode(
        a.mutation(api.questions.record, { questionUid: "missing", givenAnswer: "", isCorrect: false, gradingMethod: "exact_match", rating: 1 }),
        "NOT_FOUND",
      );
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("problems", () => {
  test("create, list, edit, read back", async () => {
    const t = newTest();
    const a = alice(t);
    const uid = await a.mutation(api.problems.create, {
      title: "Two Sum",
      difficulty: "easy",
      url: " https://leetcode.com/problems/two-sum ",
      platform: " LeetCode ",
      tags: ["Array", " hash map", "array", ""],
    });
    await a.mutation(api.problems.create, { title: "anagram", difficulty: "medium" });
    const list = await a.query(api.problems.list, {});
    expect(list.map((p) => p.title)).toEqual(["anagram", "Two Sum"]);
    expect(list[1]).toMatchObject({
      url: "https://leetcode.com/problems/two-sum",
      platform: "LeetCode",
      tags: ["array", "hash map"],
      card: null,
      attempts: 0,
      lastSolved: null,
    });
    expect(list[0].tags).toEqual([]);

    await a.mutation(api.problems.update, { uid, title: "Two Sum II", difficulty: "medium", solution: "two pointers", url: null });
    const p = await a.query(api.problems.get, { uid });
    expect(p).toMatchObject({ title: "Two Sum II", difficulty: "medium", url: null, solution: "two pointers", tags: ["array", "hash map"], attempts: [] });
    await a.mutation(api.problems.update, { uid, title: "Two Sum II", difficulty: "medium", tags: ["x"], notes: "n", platform: "LC" });
    expect(await a.query(api.problems.get, { uid })).toMatchObject({ tags: ["x"], notes: "n", platform: "LC", solution: "two pointers" });
  });

  test("an attempt schedules the problem and shows on the list, detail and Today", async () => {
    const t = newTest();
    const a = alice(t);
    const uid = await a.mutation(api.problems.create, { title: "Two Sum", difficulty: "easy" });
    expect((await a.query(api.today.summary, { now: new Date().toISOString(), dayStart: "2000-01-01T00:00:00.000Z" })).problemsDue).toEqual([]);

    await a.mutation(api.problems.logAttempt, { uid, solved: false, rating: 1, durationMinutes: 30, notes: "stuck" });
    await a.mutation(api.problems.logAttempt, { uid, solved: true, rating: 3, retention: 0.9 });
    const p = await a.query(api.problems.get, { uid });
    expect(p!.attempts.map((x) => [x.solved, x.durationMinutes])).toEqual([
      [true, null],
      [false, 30],
    ]);
    expect(p!.card).toMatchObject({ state: 1 });
    expect((await a.query(api.problems.list, {}))[0]).toMatchObject({ attempts: 2, lastSolved: true });

    const later = new Date(Date.now() + 3_600_000).toISOString();
    const today = await a.query(api.today.summary, { now: later, dayStart: "2000-01-01T00:00:00.000Z" });
    expect(today.problemsDue.map((d) => d.title)).toEqual(["Two Sum"]);
    expect(today.attemptsToday).toBe(2);

    await a.mutation(api.problems.remove, { uid });
    expect(await a.query(api.problems.list, {})).toEqual([]);
    expect((await a.query(api.users.me, {}))?.rowCounts).toMatchObject({ problems: 0, problemAttempts: 0 });
  });

  test("bad input is refused", async () => {
    const t = newTest();
    const a = alice(t);
    await expectCode(a.mutation(api.problems.create, { title: "X", difficulty: "easy", url: "javascript:alert(1)" }), "INVALID_REQUEST");
    await expectCode(a.mutation(api.problems.create, { title: " ", difficulty: "easy" }), "INVALID_REQUEST");
    await expectCode(a.mutation(api.problems.update, { uid: "missing", title: "X", difficulty: "easy" }), "NOT_FOUND");
    await expectCode(a.mutation(api.problems.logAttempt, { uid: "missing", solved: true, rating: 3 }), "NOT_FOUND");
    const uid = await a.mutation(api.problems.create, { title: "X", difficulty: "easy" });
    await expectCode(a.mutation(api.problems.logAttempt, { uid, solved: true, rating: 3, durationMinutes: -1 }), "INVALID_REQUEST");
    await expectCode(a.mutation(api.problems.logAttempt, { uid, solved: true, rating: 3, durationMinutes: 1.5 }), "INVALID_REQUEST");
  });

  test("normalizeTags matches the app's", () => {
    expect(normalizeTags([" DP ", "dp", "Graph", ""])).toBe("dp,graph");
  });
});

test("today for a brand-new user is empty", async () => {
  expect(await alice(newTest()).query(api.today.summary, { now: "2026-10-28T00:00:00.000Z", dayStart: "2026-10-28T00:00:00.000Z" })).toEqual({
    dueQuestions: 0,
    reviewsToday: 0,
    attemptsToday: 0,
    problemsDue: [],
    forecast: [],
  });
});
