import { describe, expect, test } from "vitest";
import fixture from "./fixtures/fsrs_parity.json";
import {
  cardFromRow,
  cardToRow,
  formatInterval,
  newCard,
  previewNextDue,
  retrievability,
  reviewCard,
  suggestedRating,
  type Rating,
} from "../convex/scheduling";

// The fixture is the Flutter app's own scheduler (tool/fsrs_parity_fixture.dart).
describe("parity with the Flutter app's FSRS", () => {
  for (const c of fixture.cases) {
    test(`${c.name} at ${c.retention * 100}% retention`, () => {
      let card = newCard(c.start);
      for (const r of c.reviews) {
        card = reviewCard(card, r.rating as Rating, r.at, c.retention);
        expect(card.state).toBe(r.state);
        expect(card.step).toBe(r.step);
        expect(card.stability).toBeCloseTo(r.stability, 9);
        expect(card.difficulty).toBeCloseTo(r.difficulty, 9);
        expect(card.due).toBe(r.due);
        expect(retrievability(card, card.lastReview! + 86_400_000)).toBeCloseTo(r.retrievabilityAfterADay, 9);
      }
    });
  }

  test("interval labels match", () => {
    for (const { ms, label } of fixture.intervals) expect(formatInterval(ms), `${ms}`).toBe(label);
  });
});

describe("helpers", () => {
  test("previews one due date per rating, without changing the card", () => {
    const card = newCard(0);
    const preview = previewNextDue(card, 0);
    expect(preview[1]).toBe(60_000);
    expect(preview[4]).toBeGreaterThan(preview[3]);
    expect(card).toEqual(newCard(0));
  });

  test("a card left past its last step (steps were shortened) graduates", () => {
    const card = { ...reviewCard(newCard(0), 3, 0), step: 5 };
    expect(reviewCard(card, 3, 600_000)).toMatchObject({ state: 2, step: null });
    const relearning = { ...card, state: 3 };
    expect(reviewCard(relearning, 2, 600_000)).toMatchObject({ state: 2, step: null });
    expect(reviewCard(relearning, 1, 600_000)).toMatchObject({ state: 3, step: 0 });
  });

  test("a never-reviewed card has no recall yet", () => {
    expect(retrievability(newCard(0), 1000)).toBe(0);
  });

  test("suggests Good for right and Again for wrong", () => {
    expect([suggestedRating(true), suggestedRating(false)]).toEqual([3, 1]);
  });

  test("round-trips through the stored row fields", () => {
    const card = reviewCard(newCard(Date.UTC(2026, 0, 1)), 3, Date.UTC(2026, 0, 1));
    const row = cardToRow(card);
    expect(row.nextDueAt).toBe(new Date(card.due).toISOString());
    expect(cardFromRow(row)).toEqual(card);
    expect(cardFromRow({ fsrsState: null })).toBeNull();
    expect(cardFromRow({ ...cardToRow(newCard(5)), lastReviewedAt: null })?.lastReview).toBeNull();
  });
});
