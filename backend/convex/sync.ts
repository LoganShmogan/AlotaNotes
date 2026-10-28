// Offline-first sync (Docs/quillfin_plan.md §3). The client's SQLite copy
// is the source of truth for its UI; these two functions move changes
// between it and the server.
//
// push: upserts the client's dirty rows, last-writer-wins on `updatedAt`.
//       Every row that changes gets the next value of the user's `syncSeq`.
// pull: returns rows with seq > the client's cursor, oldest first, with
//       tombstones, and the new cursor to store.
import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import { SYNC_LIMITS } from "./plans";
import { checkNoteSize, RowWriter, syncError } from "./rows";
import { findUser, requireIdentity } from "./users";
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

// Rejects the whole batch on the first bad row, so a push either lands
// completely or not at all and the client can show one clear error.
function validateRow(table: SyncedTable, row: PushRow<SyncedTable>) {
  if (row.uid.length === 0 || row.uid.length > MAX_UID_LENGTH) {
    throw syncError("INVALID_ROW", `A ${table} row has an invalid uid.`, { table, uid: row.uid });
  }
  if (row.deletedAt == null && row.data == null) {
    throw syncError("INVALID_ROW", `A ${table} row has no data and isn't deleted.`, { table, uid: row.uid });
  }
  if (table === "notes" && row.data != null) checkNoteSize((row.data as SyncedData["notes"]).body, row.uid);
}

export const push = mutation({
  args: { changes: changesValidator },
  returns: v.object({ applied: v.number(), skipped: v.number() }),
  handler: async (ctx, { changes }) => {
    await requireIdentity(ctx);
    const total = syncedTableNames.reduce((sum, table) => sum + (changes[table]?.length ?? 0), 0);
    if (total > SYNC_LIMITS.maxRowsPerPush) {
      throw syncError("BATCH_TOO_LARGE", `Push at most ${SYNC_LIMITS.maxRowsPerPush} rows at a time.`);
    }
    for (const table of syncedTableNames) {
      for (const row of changes[table] ?? []) validateRow(table, row);
    }

    const writer = await RowWriter.forCaller(ctx);
    let applied = 0;
    let skipped = 0;

    for (const table of syncedTableNames) {
      for (const row of (changes[table] ?? []) as PushRow<SyncedTable>[]) {
        // A device clock running ahead would otherwise win every conflict
        // until the real time caught up.
        const updatedAt = Math.min(row.updatedAt, writer.now);
        const deleting = row.deletedAt != null;
        const existing = await writer.get(table, row.uid);

        if (existing !== null) {
          const stale = updatedAt <= existing.updatedAt;
          // History rows never change once written; only a delete applies.
          const immutable = appendOnlyTables.has(table) && !deleting;
          if (stale || immutable) {
            skipped++;
            continue;
          }
        }

        await writer.put(table, row.uid, deleting ? undefined : row.data!, {
          existing,
          updatedAt,
          deletedAt: deleting ? Math.min(row.deletedAt!, writer.now) : undefined,
        });
        applied++;
      }
    }

    await writer.flush();
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
