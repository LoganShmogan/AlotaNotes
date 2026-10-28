// Shared pieces for the web app's data functions (folders.ts, notes.ts,
// questions.ts, problems.ts, today.ts). The web app reads Convex directly;
// every write goes through RowWriter so the phones pull it like any other
// change.
import { ConvexError } from "convex/values";
import type { Id } from "./_generated/dataModel";
import type { QueryCtx } from "./_generated/server";
import type { Row } from "./rows";
import type { SyncedTable } from "./validators";

export function notFound(what: string): never {
  throw new ConvexError({ code: "NOT_FOUND", message: `That ${what} no longer exists.` });
}

export function invalid(message: string): never {
  throw new ConvexError({ code: "INVALID_REQUEST", message });
}

/// The live rows of [table] whose [key] is [value], via [index].
export async function liveChildren<T extends SyncedTable>(
  ctx: QueryCtx,
  table: T,
  index: string,
  userId: Id<"users">,
  key: string,
  value: unknown,
): Promise<(Row<T> & { data: NonNullable<Row<T>["data"]> })[]> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const rows: Row<T>[] = await (ctx.db.query(table) as any)
    .withIndex(index, (q: any) => q.eq("userId", userId).eq(key, value))
    .collect();
  return rows.filter((r) => r.deletedAt === undefined && r.data !== undefined) as never;
}

/// Every live row of [table] for the user.
export async function allLive<T extends SyncedTable>(ctx: QueryCtx, table: T, userId: Id<"users">) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const rows: Row<T>[] = await (ctx.db.query(table) as any)
    .withIndex("by_user_uid", (q: any) => q.eq("userId", userId))
    .collect();
  return rows.filter((r) => r.deletedAt === undefined && r.data !== undefined) as (Row<T> & {
    data: NonNullable<Row<T>["data"]>;
  })[];
}

export const nowIso = (ms: number) => new Date(ms).toISOString();

/// A required, trimmed, non-empty name.
export function requireText(value: string, what: string, max = 500): string {
  const trimmed = value.trim();
  if (trimmed.length === 0) invalid(`The ${what} can't be empty.`);
  if (trimmed.length > max) invalid(`The ${what} is too long.`);
  return trimmed;
}

export function checkRetention(retention: number | undefined): number | undefined {
  if (retention !== undefined && !(retention >= 0.7 && retention <= 0.99)) invalid("Target recall is out of range.");
  return retention;
}
