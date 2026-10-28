// Offline-first sync (Docs/quillfin_plan.md §3). The client's SQLite copy
// is the source of truth for its UI; these two functions move changes
// between it and the server.
//
// push: upserts the client's dirty rows, last-writer-wins on `updatedAt`.
//       Every row that changes gets the next value of the user's `syncSeq`.
// pull: returns rows with seq > the client's cursor, oldest first, with
//       tombstones, and the new cursor to store.
import { ConvexError, v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import { SYNC_LIMITS } from "./plans";
import { findUser, getOrCreateUser, requireIdentity } from "./users";
import {
  appendOnlyTables,
  pushRow,
  syncedTableNames,
  syncedTables,
  type SyncedData,
  type SyncedTable,
} from "./validators";

const changesValidator = v.object({
  folders: v.optional(v.array(pushRow(syncedTables.folders))),
  notes: v.optional(v.array(pushRow(syncedTables.notes))),
  questions: v.optional(v.array(pushRow(syncedTables.questions))),
  questionChoices: v.optional(v.array(pushRow(syncedTables.questionChoices))),
  questionHistory: v.optional(v.array(pushRow(syncedTables.questionHistory))),
  problems: v.optional(v.array(pushRow(syncedTables.problems))),
  problemAttempts: v.optional(v.array(pushRow(syncedTables.problemAttempts))),
});

type PushRow<T extends SyncedTable> = {
  uid: string;
  updatedAt: number;
  deletedAt?: number | null;
  data?: SyncedData[T] | null;
};

const MAX_UID_LENGTH = 64;

function syncError(code: string, message: string, extra: Record<string, string | number> = {}) {
  return new ConvexError({ code, message, ...extra });
}

// Rejects the whole batch on the first bad row, so a push either lands
// completely or not at all and the client can show one clear error.
function validateRow(table: SyncedTable, row: PushRow<SyncedTable>) {
  if (row.uid.length === 0 || row.uid.length > MAX_UID_LENGTH) {
    throw syncError("INVALID_ROW", `A ${table} row has an invalid uid.`, { table, uid: row.uid });
  }
  if (row.deletedAt == null && row.data == null) {
    throw syncError("INVALID_ROW", `A ${table} row has no data and isn't deleted.`, { table, uid: row.uid });
  }
  if (table === "notes" && row.data != null) {
    const bytes = new TextEncoder().encode((row.data as SyncedData["notes"]).body).length;
    if (bytes > SYNC_LIMITS.maxNoteBytes) {
      throw syncError(
        "NOTE_TOO_LARGE",
        `A note is ${Math.ceil(bytes / 1024)} KB; the limit is ${SYNC_LIMITS.maxNoteBytes / 1024} KB.`,
        { table, uid: row.uid },
      );
    }
  }
}

export const push = mutation({
  args: { changes: changesValidator },
  returns: v.object({ applied: v.number(), skipped: v.number() }),
  handler: async (ctx, { changes }) => {
    const identity = await requireIdentity(ctx);
    const total = syncedTableNames.reduce((sum, table) => sum + (changes[table]?.length ?? 0), 0);
    if (total > SYNC_LIMITS.maxRowsPerPush) {
      throw syncError("BATCH_TOO_LARGE", `Push at most ${SYNC_LIMITS.maxRowsPerPush} rows at a time.`);
    }
    for (const table of syncedTableNames) {
      for (const row of changes[table] ?? []) validateRow(table, row);
    }

    const user = await getOrCreateUser(ctx, identity.subject);
    const now = Date.now();
    let seq = user.syncSeq;
    const rowCounts = { ...user.rowCounts };
    let applied = 0;
    let skipped = 0;

    for (const table of syncedTableNames) {
      for (const row of (changes[table] ?? []) as PushRow<SyncedTable>[]) {
        // A device clock running ahead would otherwise win every conflict
        // until the real time caught up.
        const updatedAt = Math.min(row.updatedAt, now);
        const deleting = row.deletedAt != null;
        const existing = await ctx.db
          .query(table)
          .withIndex("by_user_uid", (q) => q.eq("userId", user._id).eq("uid", row.uid))
          .unique();

        if (existing !== null) {
          const stale = updatedAt <= existing.updatedAt;
          // History rows never change once written; only a delete applies.
          const immutable = appendOnlyTables.has(table) && !deleting;
          if (stale || immutable) {
            skipped++;
            continue;
          }
        }

        const wasLive = existing !== null && existing.deletedAt === undefined;
        const liveDelta = (deleting ? 0 : 1) - (wasLive ? 1 : 0);
        const count = (rowCounts[table] ?? 0) + liveDelta;
        if (liveDelta > 0 && count > SYNC_LIMITS.maxRowsPerTable) {
          throw syncError(
            "ROW_LIMIT",
            `You've reached the limit of ${SYNC_LIMITS.maxRowsPerTable.toLocaleString("en-US")} ${table}.`,
            { table },
          );
        }
        rowCounts[table] = count;

        seq++;
        const fields = {
          updatedAt,
          seq,
          deletedAt: deleting ? Math.min(row.deletedAt!, now) : undefined,
          // A tombstone keeps no content.
          data: deleting ? undefined : row.data!,
        };
        if (existing === null) {
          await ctx.db.insert(table, { userId: user._id, uid: row.uid, ...fields } as never);
        } else {
          await ctx.db.patch(existing._id, fields as never);
        }
        applied++;
      }
    }

    if (applied > 0) await ctx.db.patch(user._id, { syncSeq: seq, rowCounts });
    return { applied, skipped };
  },
});

type PulledRow = { uid: string; updatedAt: number; deletedAt: number | null; data: unknown };

export const pull = query({
  args: { since: v.number(), limit: v.optional(v.number()) },
  handler: async (ctx, { since, limit }) => {
    const identity = await requireIdentity(ctx);
    const pageSize = Math.max(1, Math.min(limit ?? SYNC_LIMITS.defaultRowsPerPull, SYNC_LIMITS.maxRowsPerPull));
    const changes: Partial<Record<SyncedTable, PulledRow[]>> = {};
    const user = await findUser(ctx, identity.subject);
    if (user === null) return { changes, cursor: since, hasMore: false };

    // Take up to a page from every table, then keep the oldest page overall.
    // seq is unique per user, so every row at or below the last kept seq is
    // in the kept page, and the cursor never skips one.
    const candidates: { table: SyncedTable; row: Doc<SyncedTable> }[] = [];
    let anyTableFull = false;
    for (const table of syncedTableNames) {
      const rows = await ctx.db
        .query(table)
        .withIndex("by_user_seq", (q) => q.eq("userId", user._id).gt("seq", since))
        .take(pageSize);
      if (rows.length === pageSize) anyTableFull = true;
      for (const row of rows) candidates.push({ table, row });
    }
    candidates.sort((a, b) => a.row.seq - b.row.seq);
    const page = candidates.slice(0, pageSize);

    for (const { table, row } of page) {
      (changes[table] ??= []).push({
        uid: row.uid,
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt ?? null,
        data: row.data ?? null,
      });
    }
    const cursor = page.length > 0 ? page[page.length - 1].row.seq : since;
    return { changes, cursor, hasMore: candidates.length > pageSize || anyTableFull };
  },
});
