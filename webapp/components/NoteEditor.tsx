"use client";
import { useAction, useMutation, useQuery } from "convex/react";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { messageOf } from "@/lib/errors";
import { QuestionList } from "./QuestionList";
import { Button, ErrorText, inputClass, SectionLabel, Spinner } from "./ui";

const MAX_NOTE_BYTES = 200 * 1024;
const QUESTIONS_PER_GENERATION = 5;

export function NoteEditor({ noteUid, onBack, onDeleted }: { noteUid: string; onBack: () => void; onDeleted: () => void }) {
  const note = useQuery(api.notes.get, { uid: noteUid });
  if (note === undefined) return <Spinner />;
  if (note === null) {
    return (
      <div className="flex flex-col items-start gap-2">
        <p>This note no longer exists.</p>
        <Button variant="outline" onClick={onBack}>
          Back
        </Button>
      </div>
    );
  }
  return <Editor note={note} onBack={onBack} onDeleted={onDeleted} />;
}

type Note = NonNullable<ReturnType<typeof useQuery<typeof api.notes.get>>>;

function Editor({ note, onBack, onDeleted }: { note: Note; onBack: () => void; onDeleted: () => void }) {
  const update = useMutation(api.notes.update);
  const remove = useMutation(api.notes.remove);
  const generate = useAction(api.ai.generateQuestions);
  const saveGenerated = useMutation(api.questions.saveGenerated);
  const [title, setTitle] = useState(note.title);
  const [body, setBody] = useState(note.body);
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [format, setFormat] = useState<"short_answer" | "multiple_choice">("short_answer");
  const [generating, setGenerating] = useState(false);
  const dirty = title !== note.title || body !== note.body;
  const tooLarge = new TextEncoder().encode(body).length > MAX_NOTE_BYTES;

  const save = async () => {
    if (!dirty || tooLarge) return;
    setError(null);
    try {
      await update({ uid: note.uid, title, body });
      setStatus("Saved.");
    } catch (e) {
      setError(messageOf(e));
    }
  };

  // Ctrl/⌘+S saves, as in the app.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s") {
        e.preventDefault();
        void save();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  const runGeneration = async () => {
    setGenerating(true);
    setError(null);
    setStatus(null);
    try {
      if (dirty) await update({ uid: note.uid, title, body });
      const result = await generate({ noteText: body, numQuestions: QUESTIONS_PER_GENERATION, questionFormat: format });
      await saveGenerated({ noteUid: note.uid, questions: result.questions });
      setStatus(`Generated ${result.questions.length} question(s). ${result.usage.used} of ${result.usage.limit} this month.`);
    } catch (e) {
      setError(messageOf(e));
    } finally {
      setGenerating(false);
    }
  };

  return (
    <div className="mx-auto flex max-w-[760px] flex-col gap-3">
      <div className="flex items-center justify-between gap-2">
        <Button variant="ghost" className="md:hidden" onClick={onBack}>
          ← Back
        </Button>
        <div className="ml-auto flex gap-2">
          <Button
            variant="ghost"
            className="text-danger"
            onClick={async () => {
              if (!window.confirm(`Delete “${note.title}” and its questions?`)) return;
              await remove({ uid: note.uid });
              onDeleted();
            }}
          >
            Delete
          </Button>
          <Button onClick={save} disabled={!dirty || tooLarge}>
            {dirty ? "Save" : "Saved"}
          </Button>
        </div>
      </div>
      <input
        aria-label="Title"
        className={`${inputClass} font-display text-xl font-semibold`}
        value={title}
        onChange={(e) => {
          setTitle(e.target.value);
          setStatus(null);
        }}
      />
      <textarea
        aria-label="Body"
        className={`${inputClass} min-h-[40vh] max-w-[72ch] leading-relaxed`}
        value={body}
        onChange={(e) => {
          setBody(e.target.value);
          setStatus(null);
        }}
      />
      {tooLarge && <ErrorText>This note is over 200 KB. Split it into smaller notes to save it.</ErrorText>}
      {status && (
        <p role="status" className="text-sm text-success">
          {status}
        </p>
      )}
      <ErrorText>{error}</ErrorText>

      <SectionLabel>Questions</SectionLabel>
      <div className="flex flex-wrap items-center gap-2">
        <select aria-label="Question format" className={`${inputClass} w-auto`} value={format} onChange={(e) => setFormat(e.target.value as typeof format)}>
          <option value="short_answer">Short answer</option>
          <option value="multiple_choice">Multiple choice</option>
        </select>
        <Button variant="outline" onClick={runGeneration} disabled={generating || body.trim() === ""}>
          {generating ? "Generating..." : "Generate"}
        </Button>
        <span className="text-xs text-ink-soft">Uses QuillFin&apos;s AI, within your plan.</span>
      </div>
      <QuestionList noteUid={note.uid} />
    </div>
  );
}
