import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ConvexError } from "convex/values";
import { beforeEach, describe, expect, test } from "vitest";
import { answer, backend, calls, handle } from "./mocks";
import { grade, QuizSession } from "@/components/QuizSession";
import { newCard } from "@/lib/api";

const now = Date.now();
const shortAnswer = {
  uid: "q1",
  noteUid: "n1",
  noteTitle: "Cells",
  questionType: "short_answer" as const,
  prompt: "What makes ATP?",
  expectedAnswer: "Mitochondria",
  active: true,
  isManuallyEdited: false,
  createdAt: "",
  card: newCard(now),
  choices: [],
};
const mcq = {
  ...shortAnswer,
  uid: "q2",
  noteTitle: null,
  questionType: "multiple_choice" as const,
  prompt: "Which planet is largest?",
  expectedAnswer: "Jupiter",
  card: null,
  choices: [
    { uid: "c1", text: "Mars", isCorrect: false },
    { uid: "c2", text: "Jupiter", isCorrect: true },
  ],
};

beforeEach(() => backend.reset());

describe("grade", () => {
  test("matches the app's grading methods", () => {
    expect(grade(shortAnswer, "mitochondria!")).toEqual({ given: "mitochondria!", isCorrect: true, method: "exact_match" });
    expect(grade({ ...shortAnswer, expectedAnswer: "the mitochondria of the cell" }, "mitochondria cell")).toMatchObject({
      isCorrect: true,
      method: "keyword_match",
    });
    expect(grade(mcq, "Mars")).toEqual({ given: "Mars", isCorrect: false, method: "mcq_exact" });
    expect(grade({ ...mcq, choices: [] }, "Jupiter").isCorrect).toBe(false);
  });
});

describe("QuizSession", () => {
  test("loads, then grades, previews ratings and records the chosen one", async () => {
    answer("questions:due", undefined);
    const { rerender } = render(<QuizSession />);
    expect(screen.getByRole("status", { name: "Loading questions" })).toBeInTheDocument();

    answer("questions:due", [shortAnswer, mcq]);
    rerender(<QuizSession />);
    expect(screen.getByText("What makes ATP?")).toBeInTheDocument();
    expect(screen.getByText(/From “Cells” · 1 more due after this one/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Submit" })).toBeDisabled();

    await userEvent.type(screen.getByLabelText("Your answer"), "mitochondria{Enter}");
    expect(screen.getByText("Correct!")).toBeInTheDocument();
    // A new card: Again 1m, Hard 6m, Good 10m (Good is suggested).
    expect(screen.getByRole("button", { name: /Again\s*1m/ })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Hard\s*6m/ })).toBeInTheDocument();
    const good = screen.getByRole("button", { name: /Good\s*10m/ });
    expect(good).toHaveAttribute("data-suggested", "true");

    await userEvent.click(good);
    await waitFor(() => expect(screen.getByText("Which planet is largest?")).toBeInTheDocument());
    expect(calls("questions:record")).toEqual([
      { questionUid: "q1", givenAnswer: "mitochondria", isCorrect: true, gradingMethod: "exact_match", rating: 3, retention: 0.9 },
    ]);

    // Multiple choice, answered wrong, rated with the keyboard.
    expect(screen.getByText("Last one")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Mars" }));
    await userEvent.click(screen.getByRole("button", { name: "Submit" }));
    expect(screen.getByText("Incorrect. Expected: Jupiter")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Again/ })).toHaveAttribute("data-suggested", "true");
    fireEvent.keyDown(window, { key: "1" });
    await waitFor(() => expect(screen.getByText("Session done: 2 reviewed.")).toBeInTheDocument());
    expect(calls("questions:record")[1]).toMatchObject({ questionUid: "q2", isCorrect: false, gradingMethod: "mcq_exact", rating: 1 });
  });

  test("a failed save shows why and keeps the question", async () => {
    answer("questions:due", [shortAnswer]);
    handle("questions:record", () => {
      throw new ConvexError({ code: "NOT_FOUND", message: "That question no longer exists." });
    });
    render(<QuizSession />);
    await userEvent.type(screen.getByLabelText("Your answer"), "nope");
    await userEvent.click(screen.getByRole("button", { name: "Submit" }));
    await userEvent.click(screen.getByRole("button", { name: /Easy/ }));
    expect(await screen.findByRole("alert")).toHaveTextContent("That question no longer exists.");
    expect(screen.getByText("What makes ATP?")).toBeInTheDocument();
  });

  test("blank answers can't be submitted, and keys are ignored while typing", async () => {
    answer("questions:due", [shortAnswer]);
    render(<QuizSession />);
    fireEvent.submit(screen.getByLabelText("Your answer").closest("form")!);
    expect(screen.queryByText("Correct!")).not.toBeInTheDocument();
    await userEvent.type(screen.getByLabelText("Your answer"), "1");
    expect(calls("questions:record")).toEqual([]);
  });

  test("with nothing due, says so", () => {
    answer("questions:due", []);
    render(<QuizSession />);
    expect(screen.getByText("Nothing is due right now")).toBeInTheDocument();
  });
});
