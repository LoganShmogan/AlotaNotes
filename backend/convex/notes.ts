// Notes, for the web app.
import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { liveChildren, notFound, nowIso, requireText } from "./library";
import { callerUser, checkNoteSize, getRow, newUid, RowWriter } from "./rows";

const PREVIEW_CHARS = 160;

/// A folder's notes in their saved order, with a short preview each.
export const listByFolder = query({
  args: { folderUid: v.string() },
  handler: async (ctx, { folderUid }) => {
    const user = await callerUser(ctx);
    if (user === null) return [];
    const notes = await liveChildren(ctx, "notes", "by_folder", user._id, "data.folderUid", folderUid);
    return notes
      .sort((a, b) => a.data.sortOrder - b.data.sortOrder || a.data.createdAt.localeCompare(b.data.createdAt))
      .map((n) => ({
        uid: n.uid,
        title: n.data.title,
        preview: n.data.body.slice(0, PREVIEW_CHARS),
        updatedAt: n.data.updatedAt,
        sourceFilename: n.data.sourceFilename ?? null,
      }));
  },
});

export const get = query({
  args: { uid: v.string() },
  handler: async (ctx, { uid }) => {
    const user = await callerUser(ctx);
    if (user === null) return null;
    const note = await getRow(ctx, "notes", user._id, uid);
    if (note === null || note.data === undefined) return null;
    return { uid, ...note.data, sourceFilename: note.data.sourceFilename ?? null };
  },
});

export const create = mutation({
  args: { folderUid: v.string(), title: v.string(), body: v.string() },
  handler: async (ctx, { folderUid, title, body }) => {
    const writer = await RowWriter.forCaller(ctx);
    const folder = await writer.get("folders", folderUid);
    if (folder === null || folder.deletedAt !== undefined) notFound("folder");
    const uid = newUid();
    checkNoteSize(body, uid);
    // New notes go last, as in the app.
    const siblings = await liveChildren(ctx, "notes", "by_folder", writer.user._id, "data.folderUid", folderUid);
    const at = nowIso(writer.now);
    await writer.put("notes", uid, {
      folderUid,
      title: requireText(title, "title"),
      body,
      sourceFilename: null,
      sortOrder: siblings.reduce((max, n) => Math.max(max, n.data.sortOrder + 1), 0),
      createdAt: at,
      updatedAt: at,
    });
    await writer.flush();
    return uid;
  },
});

export const update = mutation({
  args: { uid: v.string(), title: v.optional(v.string()), body: v.optional(v.string()) },
  handler: async (ctx, { uid, title, body }) => {
    const writer = await RowWriter.forCaller(ctx);
    const note = await writer.get("notes", uid);
    if (note === null || note.data === undefined) notFound("note");
    if (body !== undefined) checkNoteSize(body, uid);
    await writer.put(
      "notes",
      uid,
      {
        ...note.data,
        title: title === undefined ? note.data.title : requireText(title, "title"),
        body: body ?? note.data.body,
        updatedAt: nowIso(writer.now),
      },
      { existing: note },
    );
    await writer.flush();
  },
});

/// Deletes the note and its questions.
export const remove = mutation({
  args: { uid: v.string() },
  handler: async (ctx, { uid }) => {
    const writer = await RowWriter.forCaller(ctx);
    await writer.remove("notes", uid);
    await writer.flush();
  },
});
