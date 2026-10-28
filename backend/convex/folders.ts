// Subject folders, for the web app.
import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { allLive, notFound, nowIso, requireText } from "./library";
import { callerUser, newUid, RowWriter } from "./rows";

/// Every folder, A-Z; the web app builds the tree from parentFolderUid.
export const list = query({
  args: {},
  handler: async (ctx) => {
    const user = await callerUser(ctx);
    if (user === null) return [];
    const folders = await allLive(ctx, "folders", user._id);
    return folders
      .map((f) => ({ uid: f.uid, name: f.data.name, parentFolderUid: f.data.parentFolderUid ?? null }))
      .sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: "base" }));
  },
});

export const create = mutation({
  args: { name: v.string(), parentFolderUid: v.optional(v.union(v.string(), v.null())) },
  handler: async (ctx, { name, parentFolderUid }) => {
    const writer = await RowWriter.forCaller(ctx);
    if (parentFolderUid) {
      const parent = await writer.get("folders", parentFolderUid);
      if (parent === null || parent.deletedAt !== undefined) notFound("folder");
    }
    const uid = newUid();
    await writer.put("folders", uid, {
      parentFolderUid: parentFolderUid ?? null,
      name: requireText(name, "folder name", 200),
      createdAt: nowIso(writer.now),
    });
    await writer.flush();
    return uid;
  },
});

export const rename = mutation({
  args: { uid: v.string(), name: v.string() },
  handler: async (ctx, { uid, name }) => {
    const writer = await RowWriter.forCaller(ctx);
    const folder = await writer.get("folders", uid);
    if (folder === null || folder.data === undefined) notFound("folder");
    await writer.put("folders", uid, { ...folder.data, name: requireText(name, "folder name", 200) }, { existing: folder });
    await writer.flush();
  },
});

/// Deletes the folder with its subfolders, notes and their questions.
export const remove = mutation({
  args: { uid: v.string() },
  handler: async (ctx, { uid }) => {
    const writer = await RowWriter.forCaller(ctx);
    await writer.remove("folders", uid);
    await writer.flush();
  },
});
