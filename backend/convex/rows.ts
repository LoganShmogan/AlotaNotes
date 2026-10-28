// Writing synced rows. Every change, whether pushed by an app (sync.ts) or
// made in the web app (folders.ts, notes.ts, ...), goes through RowWriter,
// so it gets the next `seq` (and so reaches every device's next pull), the
// live-row count stays right, and deletes become tombstones.
import { ConvexError } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import type { MutationCtx, QueryCtx } from "./_generated/server";
import { SYNC_LIMITS } from "./plans";
import { findUser, getOrCreateUser, requireIdentity } from "./users";
import type { SyncedData, SyncedTable } from "./validators";

export type Row<T extends SyncedTable> = Doc<T>;

export function syncError(code: string, message: string, extra: Record<string, string | number> = {}) {
  return new ConvexError({ code, message, ...extra });
}

export function checkNoteSize(body: string, uid: string) {
  const bytes = new TextEncoder().encode(body).length;
  if (bytes > SYNC_LIMITS.maxNoteBytes) {
    throw syncError(
      "NOTE_TOO_LARGE",
      `A note is ${Math.ceil(bytes / 1024)} KB; the limit is ${SYNC_LIMITS.maxNoteBytes / 1024} KB.`,
      { table: "notes", uid },
    );
  }
}

/// A new row id in the same form the app makes (32 hex characters).
export const newUid = () => crypto.randomUUID().replaceAll("-", "");

// Index lookups on a table chosen at run time, which Convex's types can't
// follow; every synced table has the indexes used here.
function byIndex(ctx: QueryCtx, table: SyncedTable, index: string, userId: Id<"users">, field: string, value: unknown) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (ctx.db.query(table) as any).withIndex(index, (q: any) => q.eq("userId", userId).eq(field, value));
}

export async function getRow<T extends SyncedTable>(ctx: QueryCtx, table: T, userId: Id<"users">, uid: string) {
  return (await byIndex(ctx, table, "by_user_uid", userId, "uid", uid).unique()) as Row<T> | null;
}

// Which tables hold children of which, for deleting from the web. The app
// deletes children itself (by cascade) and pushes their tombstones.
const CHILDREN: Partial<Record<SyncedTable, { table: SyncedTable; index: string; key: string }[]>> = {
  folders: [
    { table: "folders", index: "by_parent", key: "data.parentFolderUid" },
    { table: "notes", index: "by_folder", key: "data.folderUid" },
  ],
  notes: [{ table: "questions", index: "by_note", key: "data.noteUid" }],
  questions: [
    { table: "questionChoices", index: "by_question", key: "data.questionUid" },
    { table: "questionHistory", index: "by_question", key: "data.questionUid" },
  ],
  problems: [{ table: "problemAttempts", index: "by_problem", key: "data.problemUid" }],
};

export class RowWriter {
  private seq: number;
  private rowCounts: Record<string, number>;
  private changed = false;
  readonly now = Date.now();

  constructor(
    private ctx: MutationCtx,
    readonly user: Doc<"users">,
  ) {
    this.seq = user.syncSeq;
    this.rowCounts = { ...user.rowCounts };
  }

  /// The signed-in user's writer, creating the user on first use.
  static async forCaller(ctx: MutationCtx) {
    const identity = await requireIdentity(ctx);
    return new RowWriter(ctx, await getOrCreateUser(ctx, identity.subject));
  }

  get<T extends SyncedTable>(table: T, uid: string) {
    return getRow(this.ctx, table, this.user._id, uid);
  }

  /// Stores [uid] as live with [data], or as a tombstone when [data] is
  /// undefined, at [updatedAt] (default: now).
  async put<T extends SyncedTable>(
    table: T,
    uid: string,
    data: SyncedData[T] | undefined,
    options: { existing?: Row<T> | null; updatedAt?: number; deletedAt?: number } = {},
  ) {
    const existing = options.existing === undefined ? await this.get(table, uid) : options.existing;
    const deleting = data === undefined;
    const wasLive = existing !== null && existing.deletedAt === undefined;
    const liveDelta = (deleting ? 0 : 1) - (wasLive ? 1 : 0);
    const count = (this.rowCounts[table] ?? 0) + liveDelta;
    if (liveDelta > 0 && count > SYNC_LIMITS.maxRowsPerTable) {
      throw syncError(
        "ROW_LIMIT",
        `You've reached the limit of ${SYNC_LIMITS.maxRowsPerTable.toLocaleString("en-US")} ${table}.`,
        { table },
      );
    }
    this.rowCounts[table] = count;
    this.seq++;
    this.changed = true;
    const updatedAt = options.updatedAt ?? this.now;
    const fields = {
      updatedAt,
      seq: this.seq,
      deletedAt: deleting ? (options.deletedAt ?? updatedAt) : undefined,
      data: deleting ? undefined : data,
    };
    if (existing === null) {
      await this.ctx.db.insert(table, { userId: this.user._id, uid, ...fields } as never);
    } else {
      await this.ctx.db.patch(existing._id, fields as never);
    }
  }

  /// Deletes a live row and everything under it (a folder's subfolders and
  /// notes, their questions, those questions' choices and history).
  async remove(table: SyncedTable, uid: string) {
    const existing = await this.get(table, uid);
    if (existing === null || existing.deletedAt !== undefined) return;
    for (const child of CHILDREN[table] ?? []) {
      const rows: Row<SyncedTable>[] = await byIndex(this.ctx, child.table, child.index, this.user._id, child.key, uid).collect();
      for (const row of rows) await this.remove(child.table, row.uid);
    }
    await this.put(table, uid, undefined, { existing });
  }

  /// Saves the counters. Call once, after the last write.
  async flush() {
    if (this.changed) await this.ctx.db.patch(this.user._id, { syncSeq: this.seq, rowCounts: this.rowCounts });
  }
}

/// The caller's user for a query, or null before their first write.
export async function callerUser(ctx: QueryCtx) {
  const identity = await requireIdentity(ctx);
  return findUser(ctx, identity.subject);
}
