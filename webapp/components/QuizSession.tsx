"use client";
import Link from "next/link";
import { useMutation, useQuery } from "convex/react";
import { useCallback, useState } from "react";
import { api, gradeShortAnswer, newCard, normalizeAnswerText, suggestedRating, type Rating } from "@/lib/api";
import { messageOf } from "@/lib/errors";
import { useRetention } from "@/lib/preferences";
import { RatingButtons } from "./RatingButtons";
import { Button, Card, EmptyState, ErrorText, inputClass, Spinner } from "./ui";

type DueQuestion = NonNullable<ReturnType<typeof useDue>>[number];
type Graded = { given: string; isCorrect: boolean; method: "exact_match" | "keyword_match" | "mcq_exact" };

function useDue(now: string) {
  return useQuery(api.questions.due, { now });
}

export function grade(question: Pick<DueQuestion, "questionType" | "expectedAnswer" | "choices">, given: string): Graded {
  if (question.questionType === "multiple_choice") {
    const correct = question.choices.find((c) => c.isCorrect);
    return { given, isCorrect: correct !== undefined && correct.text === given, method: "mcq_exact" };
  }
  const exact = normalizeAnswerText(question.expectedAnswer) === normalizeAnswerText(given);
  return { given, isCorrect: gradeShortAnswer(question.expectedAnswer, given), method: exact ? "exact_match" : "keyword_match" };
}

/// One quiz session over what's due when it starts. The list is taken once,
/// so questions don't shift underneath you as reviews are recorded.
export function QuizSession() {
  const [startedAt] = useState(() => new Date().toISOString());
  const due = useDue(startedAt);
  const [queue, setQueue] = useState<DueQuestion[] | null>(null);
  if (queue === null && due !== undefined) setQueue(due);
  if (queue === null) return <Spinner label="Loading questions" />;
  return <Session queue={queue} />;
}

function Session({ queue }: { queue: DueQuestion[] }) {
  const record = useMutation(api.questions.record);
  const [retention] = useRetention();
  const [index, setIndex] = useState(0);
  const [answer, setAnswer] = useState("");
  const [graded, setGraded] = useState<Graded | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const question = queue[index];

  const rate = useCallback(
    async (rating: Rating) => {
      if (!graded || saving) return;
      setSaving(true);
      setError(null);
      try {
        await record({
          questionUid: question.uid,
          givenAnswer: graded.given,
          isCorrect: graded.isCorrect,
          gradingMethod: graded.method,
          rating,
          retention,
        });
        setIndex((i) => i + 1);
        setAnswer("");
        setGraded(null);
      } catch (e) {
        setError(messageOf(e));
      } finally {
        setSaving(false);
      }
    },
    [graded, saving, record, question, retention],
  );

  if (queue.length === 0) {
    return (
      <EmptyState title="Nothing is due right now">
        <Link className="text-fin underline" href="/today">
          Back to Today
        </Link>
      </EmptyState>
    );
  }
  if (index >= queue.length) {
    return (
      <EmptyState title={`Session done: ${queue.length} reviewed.`}>
        <p>Nothing else is due right now.</p>
        <Link className="text-fin underline" href="/today">
          Back to Today
        </Link>
      </EmptyState>
    );
  }

  const remaining = queue.length - index - 1;
  const submit = (given: string) => {
    if (graded || given.trim() === "") return;
    setGraded(grade(question, given));
  };

  return (
    <div className="mx-auto flex max-w-[640px] flex-col gap-4">
      <p className="text-sm text-ink-soft">
        {question.noteTitle ? `From “${question.noteTitle}” · ` : ""}
        {remaining === 0 ? "Last one" : `${remaining} more due after this one`}
      </p>
      <Card>
        <p className="text-lg font-medium">{question.prompt}</p>
      </Card>

      {question.questionType === "multiple_choice" ? (
        <div className="flex flex-col gap-2">
          {question.choices.map((c) => {
            const state = !graded ? "" : c.isCorrect ? "border-success" : c.text === graded.given ? "border-danger" : "";
            return (
              <button
                key={c.uid}
                type="button"
                disabled={graded !== null}
                onClick={() => setAnswer(c.text)}
                aria-pressed={answer === c.text}
                className={`rounded-[var(--radius-control)] border-2 bg-surface px-4 py-3 text-left aria-pressed:border-fin ${state || "border-line"}`}
              >
                {c.text}
              </button>
            );
          })}
        </div>
      ) : (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            submit(answer);
          }}
        >
          <input
            aria-label="Your answer"
            autoFocus
            className={inputClass}
            disabled={graded !== null}
            value={answer}
            onChange={(e) => setAnswer(e.target.value)}
            placeholder="Type your answer"
          />
        </form>
      )}

      {!graded ? (
        <Button onClick={() => submit(answer)} disabled={answer.trim() === ""}>
          Submit
        </Button>
      ) : (
        <div className="sticky bottom-20 flex flex-col gap-3 rounded-[var(--radius-card)] bg-paper py-2 sm:static">
          <p role="status" className={graded.isCorrect ? "font-semibold text-success" : "font-semibold text-danger"}>
            {graded.isCorrect ? "Correct!" : `Incorrect. Expected: ${question.expectedAnswer}`}
          </p>
          <RatingButtons
            card={question.card ?? newCard(Date.now())}
            now={Date.now()}
            retention={retention}
            suggested={suggestedRating(graded.isCorrect)}
            disabled={saving}
            onRate={rate}
          />
          <ErrorText>{error}</ErrorText>
        </div>
      )}
    </div>
  );
}
