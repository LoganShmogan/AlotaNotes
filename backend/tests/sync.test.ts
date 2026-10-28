import { describe, expect, test } from "vitest";
import { api } from "../convex/_generated/api";
import { SYNC_LIMITS } from "../convex/plans";
import { as, expectCode, newTest } from "./setup";

const folder = (name = "Biology") => ({ parentFolderUid: null, name, createdAt: "2026-10-01T00:00:00.000Z" });
const note = (body = "Mitochondria make ATP.") => ({
  folderUid: "f1",
  title: "Cells",
  body,
  sourceFilename: null,
  sortOrder: 0,
  createdAt: "2026-10-01T00:00:00.000Z",
  updatedAt: "2026-10-01T00:00:00.000Z",
});
const attempt = () => ({
  problemUid: "p1",
  attemptedAt: "2026-10-02T00:00:00.000Z",
  solved: true,
  durationMinutes: 25,
  rating: 3 as const,
  notes: "",
  nextDueAfter: "2026-10-05T00:00:00.000Z",
  stabilityAfter: 3.1,
});

describe("sync", () => {
  test("push and pull need a signed-in user", async () => {
    const t = newTest();
    await expectCode(t.mutation(api.sync.push, { changes: {} }), "UNAUTHENTICATED");
    await expectCode(t.query(api.sync.pull, { since: 0 }), "UNAUTHENTICATED");
  });

  test("pull before any push returns nothing at the same cursor", async () => {
    const alice = as(newTest(), "user_alice");
    expect(await alice.query(api.sync.pull, { since: 7 })).toEqual({ changes: {}, cursor: 7, hasMore: false });
  });

  test("pushed rows come back from pull with a cursor past them", async () => {
    const alice = as(newTest(), "user_alice");
    const result = await alice.mutation(api.sync.push, {
      changes: {
        folders: [{ uid: "f1", updatedAt: 1000, data: folder() }],
        notes: [{ uid: "n1", updatedAt: 1000, data: note() }],
      },
    });
    expect(result).toEqual({ applied: 2, skipped: 0 });

    const pulled = await alice.query(api.sync.pull, { since: 0 });
    expect(pulled.cursor).toBe(2);
    expect(pulled.hasMore).toBe(false);
    expect(pulled.changes.folders).toEqual([{ uid: "f1", updatedAt: 1000, deletedAt: null, data: folder() }]);
    expect(pulled.changes.notes?.[0].data).toEqual(note());

    expect(await alice.query(api.sync.pull, { since: 2 })).toEqual({ changes: {}, cursor: 2, hasMore: false });
  });

  test("last writer wins on updatedAt; older and equal writes are skipped", async () => {
    const alice = as(newTest(), "user_alice");
    await alice.mutation(api.sync.push, { changes: { folders: [{ uid: "f1", updatedAt: 2000, data: folder("B") }] } });

    const older = await alice.mutation(api.sync.push, {
      changes: { folders: [{ uid: "f1", updatedAt: 1000, data: folder("Old") }] },
    });
    const retry = await alice.mutation(api.sync.push, {
      changes: { folders: [{ uid: "f1", updatedAt: 2000, data: folder("B") }] },
    });
    expect(older).toEqual({ applied: 0, skipped: 1 });
    expect(retry).toEqual({ applied: 0, skipped: 1 });

    await alice.mutation(api.sync.push, { changes: { folders: [{ uid: "f1", updatedAt: 3000, data: folder("New") }] } });
    const pulled = await alice.query(api.sync.pull, { since: 0 });
    expect(pulled.changes.folders).toEqual([{ uid: "f1", updatedAt: 3000, deletedAt: null, data: folder("New") }]);
    // Only the changed row moves the cursor on.
    expect(pulled.cursor).toBe(2);
  });

  test("a tombstone drops the row's data and frees its place in the row count", async () => {
    const alice = as(newTest(), "user_alice");
    await alice.mutation(api.sync.push, { changes: { folders: [{ uid: "f1", updatedAt: 1000, data: folder() }] } });
    expect((await alice.query(api.users.me, {}))?.rowCounts).toEqual({ folders: 1 });

    await alice.mutation(api.sync.push, { changes: { folders: [{ uid: "f1", updatedAt: 2000, deletedAt: 2000 }] } });
    const pulled = await alice.query(api.sync.pull, { since: 1 });
    expect(pulled.changes.folders).toEqual([{ uid: "f1", updatedAt: 2000, deletedAt: 2000, data: null }]);
    expect((await alice.query(api.users.me, {}))?.rowCounts).toEqual({ folders: 0 });

    // A later edit from another device brings it back.
    await alice.mutation(api.sync.push, { changes: { folders: [{ uid: "f1", updatedAt: 3000, data: folder() }] } });
    expect((await alice.query(api.users.me, {}))?.rowCounts).toEqual({ folders: 1 });
  });

  test("a tombstone for a row the server never saw is stored", async () => {
    const alice = as(newTest(), "user_alice");
    const result = await alice.mutation(api.sync.push, {
      changes: { notes: [{ uid: "n9", updatedAt: 1000, deletedAt: 1000, data: null }] },
    });
    expect(result.applied).toBe(1);
    expect((await alice.query(api.users.me, {}))?.rowCounts).toEqual({ notes: 0 });
  });

  test("history rows can't be edited once written, only deleted", async () => {
    const alice = as(newTest(), "user_alice");
    await alice.mutation(api.sync.push, { changes: { problemAttempts: [{ uid: "a1", updatedAt: 1000, data: attempt() }] } });
    const edit = await alice.mutation(api.sync.push, {
      changes: { problemAttempts: [{ uid: "a1", updatedAt: 2000, data: { ...attempt(), solved: false } }] },
    });
    expect(edit).toEqual({ applied: 0, skipped: 1 });

    await alice.mutation(api.sync.push, { changes: { problemAttempts: [{ uid: "a1", updatedAt: 3000, deletedAt: 3000 }] } });
    const pulled = await alice.query(api.sync.pull, { since: 0 });
    expect(pulled.changes.problemAttempts).toEqual([{ uid: "a1", updatedAt: 3000, deletedAt: 3000, data: null }]);
  });

  test("an updatedAt in the future is clamped to the server's clock", async () => {
    const alice = as(newTest(), "user_alice");
    const future = Date.now() + 365 * 24 * 3600 * 1000;
    await alice.mutation(api.sync.push, { changes: { folders: [{ uid: "f1", updatedAt: future, data: folder() }] } });
    const pulled = await alice.query(api.sync.pull, { since: 0 });
    expect(pulled.changes.folders?.[0].updatedAt).toBeLessThanOrEqual(Date.now());
  });

  test("users only ever see their own rows", async () => {
    const t = newTest();
    await as(t, "user_alice").mutation(api.sync.push, {
      changes: { folders: [{ uid: "f1", updatedAt: 1000, data: folder("Alice's") }] },
    });
    await as(t, "user_bob").mutation(api.sync.push, {
      changes: { folders: [{ uid: "f1", updatedAt: 1000, data: folder("Bob's") }] },
    });
    const bob = await as(t, "user_bob").query(api.sync.pull, { since: 0 });
    expect(bob.changes.folders).toHaveLength(1);
    expect(bob.changes.folders?.[0].data).toEqual(folder("Bob's"));
  });

  test("pull pages across tables in seq order without skipping rows", async () => {
    const alice = as(newTest(), "user_alice");
    // Interleave tables so each page mixes them.
    for (let i = 0; i < 5; i++) {
      await alice.mutation(api.sync.push, {
        changes: {
          folders: [{ uid: `f${i}`, updatedAt: 1000, data: folder(`F${i}`) }],
          notes: [{ uid: `n${i}`, updatedAt: 1000, data: note() }],
        },
      });
    }
    const seen: string[] = [];
    let since = 0;
    let pages = 0;
    for (;;) {
      const page = await alice.query(api.sync.pull, { since, limit: 3 });
      for (const rows of Object.values(page.changes)) for (const row of rows ?? []) seen.push(row.uid);
      expect(page.cursor).toBeGreaterThanOrEqual(since);
      since = page.cursor;
      pages++;
      if (!page.hasMore) break;
    }
    expect(seen.sort()).toEqual(["f0", "f1", "f2", "f3", "f4", "n0", "n1", "n2", "n3", "n4"]);
    expect(pages).toBeGreaterThanOrEqual(4);
  });

  test("a note over the size limit rejects the whole push", async () => {
    const alice = as(newTest(), "user_alice");
    const data = await expectCode(
      alice.mutation(api.sync.push, {
        changes: {
          folders: [{ uid: "f1", updatedAt: 1000, data: folder() }],
          notes: [{ uid: "n1", updatedAt: 1000, data: note("é".repeat(SYNC_LIMITS.maxNoteBytes / 2 + 1)) }],
        },
      }),
      "NOTE_TOO_LARGE",
    );
    expect(data.uid).toBe("n1");
    expect((await alice.query(api.sync.pull, { since: 0 })).changes).toEqual({});
  });

  test("a push over the batch size is rejected", async () => {
    const alice = as(newTest(), "user_alice");
    const folders = Array.from({ length: SYNC_LIMITS.maxRowsPerPush + 1 }, (_, i) => ({
      uid: `f${i}`,
      updatedAt: 1000,
      data: folder(),
    }));
    await expectCode(alice.mutation(api.sync.push, { changes: { folders } }), "BATCH_TOO_LARGE");
  });

  test("rows with a bad uid, or no data and no delete, are rejected", async () => {
    const alice = as(newTest(), "user_alice");
    await expectCode(
      alice.mutation(api.sync.push, { changes: { folders: [{ uid: "", updatedAt: 1, data: folder() }] } }),
      "INVALID_ROW",
    );
    await expectCode(
      alice.mutation(api.sync.push, { changes: { folders: [{ uid: "x".repeat(65), updatedAt: 1, data: folder() }] } }),
      "INVALID_ROW",
    );
    await expectCode(alice.mutation(api.sync.push, { changes: { folders: [{ uid: "f1", updatedAt: 1 }] } }), "INVALID_ROW");
  });

  test("new rows past the per-table limit are rejected; edits still apply", async () => {
    const t = newTest();
    const alice = as(t, "user_alice");
    await alice.mutation(api.sync.push, { changes: { folders: [{ uid: "f1", updatedAt: 1000, data: folder() }] } });
    await t.run(async (ctx) => {
      const user = (await ctx.db.query("users").first())!;
      await ctx.db.patch(user._id, { rowCounts: { folders: SYNC_LIMITS.maxRowsPerTable } });
    });

    await expectCode(
      alice.mutation(api.sync.push, { changes: { folders: [{ uid: "f2", updatedAt: 1000, data: folder() }] } }),
      "ROW_LIMIT",
    );
    const edit = await alice.mutation(api.sync.push, {
      changes: { folders: [{ uid: "f1", updatedAt: 2000, data: folder("Renamed") }] },
    });
    expect(edit.applied).toBe(1);
  });
});
