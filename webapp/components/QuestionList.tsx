"use client";
import { useMutation, useQuery } from "convex/react";
import { useState } from "react";
import { api } from "@/lib/api";
import { messageOf } from "@/lib/errors";
import { Button, Dialog, ErrorText, Field, inputClass, Pill, Spinner } from "./ui";

type Question = NonNullable<ReturnType<typeof useQuery<typeof api.questions.listByNote>>>[number];

export function QuestionList({ noteUid }: { noteUid: string }) {
  const questions = useQuery(api.questions.listByNote, { noteUid });
  const setActive = useMutation(api.questions.setActive);
  const remove = useMutation(api.questions.remove);
  const [editing, setEditing] = useState<Question | null>(null);
  if (questions === undefined) return <Spinner />;
  if (questions.length === 0) return <p className="text-sm text-ink-soft">No questions yet. Generate some from this note.</p>;
  return (
    <>
      <ul className="flex flex-col gap-2" aria-label="Questions">
        {questions.map((q) => (
          <li key={q.uid} className="flex items-start justify-between gap-3 rounded-[var(--radius-card)] border border-line bg-surface p-3">
            <div className="min-w-0">
              <p className={q.active ? "" : "text-ink-soft line-through"}>{q.prompt}</p>
              <p className="mt-1 flex gap-1 text-xs text-ink-soft">
                <Pill>{q.questionType === "multiple_choice" ? "Multiple choice" : "Short answer"}</Pill>
                {q.isManuallyEdited && <Pill>edited</Pill>}
              </p>
            </div>
            <div className="flex shrink-0 gap-1">
              <Button variant="ghost" onClick={() => setEditing(q)}>
                Edit
              </Button>
              <Button variant="ghost" onClick={() => setActive({ uid: q.uid, active: !q.active })}>
                {q.active ? "Pause" : "Resume"}
              </Button>
              <Button variant="ghost" className="text-danger" onClick={() => remove({ uid: q.uid })}>
                Delete
              </Button>
            </div>
          </li>
        ))}
      </ul>
      {editing && <QuestionEditor key={editing.uid} question={editing} onClose={() => setEditing(null)} />}
    </>
  );
}

function QuestionEditor({ question, onClose }: { question: Question; onClose: () => void }) {
  const update = useMutation(api.questions.update);
  const [prompt, setPrompt] = useState(question.prompt);
  const [answer, setAnswer] = useState(question.expectedAnswer);
  const [choices, setChoices] = useState(question.choices.map((c) => ({ text: c.text, isCorrect: c.isCorrect })));
  const [error, setError] = useState<string | null>(null);
  const mcq = question.questionType === "multiple_choice";
  return (
    <Dialog open onClose={onClose} title="Edit question">
      <Field label="Question prompt">
        <textarea className={inputClass} value={prompt} onChange={(e) => setPrompt(e.target.value)} />
      </Field>
      {mcq ? (
        <fieldset className="flex flex-col gap-2">
          <legend className="text-sm font-medium">Choices (pick the correct one)</legend>
          {choices.map((c, i) => (
            <div key={i} className="flex items-center gap-2">
              <input
                type="radio"
                name="correct"
                aria-label={`Choice ${i + 1} is correct`}
                checked={c.isCorrect}
                onChange={() => setChoices(choices.map((x, j) => ({ ...x, isCorrect: i === j })))}
              />
              <input
                aria-label={`Choice ${i + 1}`}
                className={inputClass}
                value={c.text}
                onChange={(e) => setChoices(choices.map((x, j) => (i === j ? { ...x, text: e.target.value } : x)))}
              />
            </div>
          ))}
        </fieldset>
      ) : (
        <Field label="Expected answer">
          <input className={inputClass} value={answer} onChange={(e) => setAnswer(e.target.value)} />
        </Field>
      )}
      <ErrorText>{error}</ErrorText>
      <div className="flex justify-end gap-2">
        <Button variant="ghost" onClick={onClose}>
          Cancel
        </Button>
        <Button
          onClick={async () => {
            try {
              const expectedAnswer = mcq ? (choices.find((c) => c.isCorrect)?.text ?? answer) : answer;
              await update({ uid: question.uid, prompt, expectedAnswer, ...(mcq ? { choices } : {}) });
              onClose();
            } catch (e) {
              setError(messageOf(e));
            }
          }}
        >
          Save
        </Button>
      </div>
    </Dialog>
  );
}
