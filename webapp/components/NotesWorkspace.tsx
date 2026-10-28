"use client";
import { useMutation, useQuery } from "convex/react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { api } from "@/lib/api";
import { NameDialog } from "./NameDialog";
import { NoteEditor } from "./NoteEditor";
import { Button, EmptyState, Spinner } from "./ui";

type Folder = { uid: string; name: string; parentFolderUid: string | null };

/// Notes (Docs/quillfin_plan.md §5): on phones, the folder list, then a
/// folder, then the editor full-screen; from expanded (840) up, folders and
/// notes on the left and the open note on the right. The selection lives in
/// the URL (?folder=&note=), so back and forward work.
export function NotesWorkspace() {
  const params = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const folderUid = params.get("folder");
  const noteUid = params.get("note");
  const folders = useQuery(api.folders.list, {});

  const go = (next: { folder?: string | null; note?: string | null }) => {
    const q = new URLSearchParams();
    const folder = next.folder === undefined ? folderUid : next.folder;
    const note = next.note === undefined ? noteUid : next.note;
    if (folder) q.set("folder", folder);
    if (note) q.set("note", note);
    router.push(q.size ? `${pathname}?${q}` : pathname);
  };

  if (folders === undefined) return <Spinner />;

  return (
    <div className="grid gap-6 md:grid-cols-[360px_1fr]">
      <div className={noteUid ? "hidden md:block" : ""}>
        <FolderBrowser folders={folders} folderUid={folderUid} noteUid={noteUid} go={go} />
      </div>
      <div className={noteUid ? "" : "hidden md:block"}>
        {noteUid ? (
          <NoteEditor key={noteUid} noteUid={noteUid} onBack={() => go({ note: null })} onDeleted={() => go({ note: null })} />
        ) : (
          <EmptyState title="Select a note to edit it here." />
        )}
      </div>
    </div>
  );
}

function FolderBrowser({
  folders,
  folderUid,
  noteUid,
  go,
}: {
  folders: Folder[];
  folderUid: string | null;
  noteUid: string | null;
  go: (next: { folder?: string | null; note?: string | null }) => void;
}) {
  const createFolder = useMutation(api.folders.create);
  const renameFolder = useMutation(api.folders.rename);
  const removeFolder = useMutation(api.folders.remove);
  const createNote = useMutation(api.notes.create);
  const [dialog, setDialog] = useState<null | "folder" | "subfolder" | "rename" | "note">(null);
  const current = folders.find((f) => f.uid === folderUid) ?? null;
  const children = folders.filter((f) => f.parentFolderUid === (current?.uid ?? null));
  const parent = current?.parentFolderUid ? folders.find((f) => f.uid === current.parentFolderUid) : null;

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between gap-2">
        {current ? (
          <button type="button" className="text-sm text-fin" onClick={() => go({ folder: parent?.uid ?? null, note: null })}>
            ← {parent?.name ?? "All folders"}
          </button>
        ) : (
          <span className="text-sm text-ink-soft">Subject folders</span>
        )}
        <div className="flex gap-2">
          {current && (
            <Button variant="outline" onClick={() => setDialog("note")}>
              New note
            </Button>
          )}
          <Button variant={current ? "ghost" : "primary"} onClick={() => setDialog(current ? "subfolder" : "folder")}>
            New folder
          </Button>
        </div>
      </div>

      {current && (
        <div className="flex items-center justify-between">
          <h2 className="text-xl font-semibold">{current.name}</h2>
          <div className="flex gap-1">
            <Button variant="ghost" onClick={() => setDialog("rename")}>
              Rename
            </Button>
            <Button
              variant="ghost"
              className="text-danger"
              onClick={async () => {
                if (!window.confirm(`Delete “${current.name}” and everything in it? This also removes it from your other devices.`)) return;
                await removeFolder({ uid: current.uid });
                go({ folder: parent?.uid ?? null, note: null });
              }}
            >
              Delete
            </Button>
          </div>
        </div>
      )}

      <ul className="flex flex-col gap-1" aria-label="Folders">
        {children.map((f) => (
          <li key={f.uid}>
            <button
              type="button"
              onClick={() => go({ folder: f.uid, note: null })}
              className="flex w-full items-center gap-2 rounded-[var(--radius-control)] px-3 py-2 text-left hover:bg-tint"
            >
              <span aria-hidden>📁</span> {f.name}
            </button>
          </li>
        ))}
      </ul>

      {current ? (
        <FolderNotes folderUid={current.uid} noteUid={noteUid} open={(uid) => go({ note: uid })} />
      ) : (
        children.length === 0 && <EmptyState title="No folders yet">Make one to start writing notes.</EmptyState>
      )}

      <NameDialog
        open={dialog === "folder" || dialog === "subfolder"}
        title={dialog === "subfolder" ? `New folder in ${current?.name}` : "New subject folder"}
        label="Folder name"
        submitLabel="Create"
        onClose={() => setDialog(null)}
        onSubmit={async (name) => {
          const uid = await createFolder({ name, parentFolderUid: dialog === "subfolder" ? current!.uid : null });
          if (dialog === "folder") go({ folder: uid, note: null });
        }}
      />
      {current && (
        <NameDialog
          key={current.uid}
          open={dialog === "rename"}
          title="Rename folder"
          label="Folder name"
          initial={current.name}
          onClose={() => setDialog(null)}
          onSubmit={async (name) => {
            await renameFolder({ uid: current.uid, name });
          }}
        />
      )}
      <NameDialog
        open={dialog === "note"}
        title="New note"
        label="Title"
        submitLabel="Create"
        onClose={() => setDialog(null)}
        onSubmit={async (title) => {
          const uid = await createNote({ folderUid: current!.uid, title, body: "" });
          go({ note: uid });
        }}
      />
    </div>
  );
}

function FolderNotes({ folderUid, noteUid, open }: { folderUid: string; noteUid: string | null; open: (uid: string) => void }) {
  const notes = useQuery(api.notes.listByFolder, { folderUid });
  if (notes === undefined) return <Spinner />;
  if (notes.length === 0) return <EmptyState title="Empty">Use New note or New folder to add something.</EmptyState>;
  return (
    <ul className="flex flex-col gap-2" aria-label="Notes">
      {notes.map((n) => (
        <li key={n.uid}>
          <button
            type="button"
            onClick={() => open(n.uid)}
            aria-current={n.uid === noteUid ? "true" : undefined}
            className="w-full rounded-[var(--radius-card)] border border-line bg-surface p-3 text-left hover:bg-tint aria-[current=true]:border-fin"
          >
            <p className="font-semibold">{n.title}</p>
            {n.preview && <p className="line-clamp-2 text-sm text-ink-soft">{n.preview}</p>}
          </button>
        </li>
      ))}
    </ul>
  );
}
