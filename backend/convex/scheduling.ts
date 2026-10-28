// FSRS scheduling, a direct port of the Dart `fsrs` 2.0.1 package's
// Scheduler.reviewCard as the Flutter app uses it (lib/core/scheduling.dart:
// default parameters, learning steps 1m and 10m, relearning step 10m,
// fuzzing off). A port rather than ts-fsrs, whose defaults and step handling
// differ: a card reviewed on the web must come out exactly as it would on a
// phone. tests/fixtures/fsrs_parity.json, generated from the Dart code by
// tool/fsrs_parity_fixture.dart, checks that.
//
// Times are milliseconds since the epoch; the stored rows keep ISO strings.

export const STATE_LEARNING = 1;
export const STATE_REVIEW = 2;
export const STATE_RELEARNING = 3;

export type Rating = 1 | 2 | 3 | 4; // Again, Hard, Good, Easy
export const RATINGS: Rating[] = [1, 2, 3, 4];
export const RATING_LABELS: Record<Rating, string> = { 1: "Again", 2: "Hard", 3: "Good", 4: "Easy" };

export type SrsCard = {
  state: number;
  step: number | null;
  stability: number | null;
  difficulty: number | null;
  due: number;
  lastReview: number | null;
};

export const DEFAULT_RETENTION = 0.9;
export const MIN_RETENTION = 0.75;
export const MAX_RETENTION = 0.97;

const W = [
  0.2172, 1.1771, 3.2602, 16.1507, 7.0114, 0.57, 2.0966, 0.0069, 1.5261, 0.112, 1.0178, 1.849, 0.1133, 0.3127,
  2.2934, 0.2191, 3.0004, 0.7536, 0.3332, 0.1437, 0.2,
];
const MINUTE = 60_000;
const DAY = 86_400_000;
const LEARNING_STEPS = [1 * MINUTE, 10 * MINUTE];
const RELEARNING_STEPS = [10 * MINUTE];
const MAX_INTERVAL_DAYS = 36500;
const STABILITY_MIN = 0.001;
const DECAY = -W[20];
const FACTOR = Math.pow(0.9, 1 / DECAY) - 1;

const clampDifficulty = (d: number) => Math.min(Math.max(d, 1), 10);
const clampStability = (s: number) => Math.max(s, STABILITY_MIN);
const initialStability = (r: Rating) => clampStability(W[r - 1]);
const initialDifficulty = (r: Rating) => clampDifficulty(W[4] - Math.exp(W[5] * (r - 1)) + 1);

function nextIntervalDays(stability: number, retention: number): number {
  const days = Math.round((stability / FACTOR) * (Math.pow(retention, 1 / DECAY) - 1));
  return Math.min(Math.max(days, 1), MAX_INTERVAL_DAYS);
}

function shortTermStability(stability: number, r: Rating): number {
  let increase = Math.exp(W[17] * (r - 3 + W[18])) * Math.pow(stability, -W[19]);
  if (r >= 3) increase = Math.max(increase, 1);
  return clampStability(stability * increase);
}

function nextDifficulty(difficulty: number, r: Rating): number {
  const delta = -(W[6] * (r - 3));
  const damped = difficulty + ((10 - difficulty) * delta) / 9;
  return clampDifficulty(W[7] * initialDifficulty(4) + (1 - W[7]) * damped);
}

function nextStability(difficulty: number, stability: number, retrievability: number, r: Rating): number {
  let next: number;
  if (r === 1) {
    const longTerm = W[11] * Math.pow(difficulty, -W[12]) * (Math.pow(stability + 1, W[13]) - 1) * Math.exp((1 - retrievability) * W[14]);
    next = Math.min(longTerm, stability / Math.exp(W[17] * W[18]));
  } else {
    const hardPenalty = r === 2 ? W[15] : 1;
    const easyBonus = r === 4 ? W[16] : 1;
    next =
      stability *
      (1 + Math.exp(W[8]) * (11 - difficulty) * Math.pow(stability, -W[9]) * (Math.exp((1 - retrievability) * W[10]) - 1) * hardPenalty * easyBonus);
  }
  return clampStability(next);
}

// Whole days, truncated, as Dart's Duration.inDays.
const wholeDays = (ms: number) => Math.trunc(ms / DAY);

// The package's own retrievability, in whole elapsed days, which is what
// the review formulas use. (`retrievability` below is the display version.)
function packageRetrievability(card: SrsCard, now: number): number {
  if (card.lastReview === null) return 0;
  const elapsed = Math.max(0, wholeDays(now - card.lastReview));
  return Math.pow(1 + (FACTOR * elapsed) / card.stability!, DECAY);
}

/// A never-reviewed card, due straight away.
export function newCard(now: number): SrsCard {
  return { state: STATE_LEARNING, step: 0, stability: null, difficulty: null, due: now, lastReview: null };
}

function stepInterval(steps: number[], card: SrsCard, r: Rating, retention: number): number {
  // A card left on a step past the end (steps were shortened) graduates.
  if (steps.length === 0 || (card.step! >= steps.length && r !== 1)) {
    card.state = STATE_REVIEW;
    card.step = null;
    return nextIntervalDays(card.stability!, retention) * DAY;
  }
  switch (r) {
    case 1:
      card.step = 0;
      return steps[0];
    case 2:
      if (card.step === 0 && steps.length === 1) return steps[0] * 1.5;
      if (card.step === 0) return Math.trunc((steps[0] + steps[1]) / 2);
      return steps[card.step!];
    case 3:
      if (card.step! + 1 === steps.length) {
        card.state = STATE_REVIEW;
        card.step = null;
        return nextIntervalDays(card.stability!, retention) * DAY;
      }
      card.step = card.step! + 1;
      return steps[card.step];
    case 4:
      card.state = STATE_REVIEW;
      card.step = null;
      return nextIntervalDays(card.stability!, retention) * DAY;
  }
}

/// The card after a review with [rating] at [now].
export function reviewCard(input: SrsCard, rating: Rating, now: number, retention = DEFAULT_RETENTION): SrsCard {
  const card = { ...input };
  const sinceLast = card.lastReview === null ? null : wholeDays(now - card.lastReview);
  const sameDay = sinceLast !== null && sinceLast < 1;
  let interval: number;

  if (card.state === STATE_REVIEW) {
    card.stability = sameDay
      ? shortTermStability(card.stability!, rating)
      : nextStability(card.difficulty!, card.stability!, packageRetrievability(card, now), rating);
    card.difficulty = nextDifficulty(card.difficulty!, rating);
    if (rating === 1) {
      card.state = STATE_RELEARNING;
      card.step = 0;
      interval = RELEARNING_STEPS[0];
    } else {
      interval = nextIntervalDays(card.stability, retention) * DAY;
    }
  } else {
    if (card.stability === null && card.difficulty === null) {
      card.stability = initialStability(rating);
      card.difficulty = initialDifficulty(rating);
    } else if (sameDay) {
      card.stability = shortTermStability(card.stability!, rating);
      card.difficulty = nextDifficulty(card.difficulty!, rating);
    } else {
      card.stability = nextStability(card.difficulty!, card.stability!, packageRetrievability(card, now), rating);
      card.difficulty = nextDifficulty(card.difficulty!, rating);
    }
    const steps = card.state === STATE_RELEARNING ? RELEARNING_STEPS : LEARNING_STEPS;
    interval = stepInterval(steps, card, rating, retention);
  }

  card.due = now + interval;
  card.lastReview = now;
  return card;
}

/// When each rating would bring the card back, for the rating buttons.
export function previewNextDue(card: SrsCard, now: number, retention = DEFAULT_RETENTION): Record<Rating, number> {
  return { 1: 0, 2: 0, 3: 0, 4: 0, ...Object.fromEntries(RATINGS.map((r) => [r, reviewCard(card, r, now, retention).due])) };
}

/// Probability of recalling the card now, with fractional elapsed days (the
/// app's display version; see lib/core/scheduling.dart).
export function retrievability(card: SrsCard, now: number): number {
  if (card.lastReview === null || card.stability === null) return 0;
  const elapsed = Math.max(0, Math.floor((now - card.lastReview) / 1000)) / 86400;
  return Math.pow(1 + (FACTOR * elapsed) / card.stability, DECAY);
}

export const suggestedRating = (correct: boolean): Rating => (correct ? 3 : 1);

/// "1m", "10m", "3h", "4d", "2mo", "1.5y", as on the app's rating buttons.
export function formatInterval(ms: number): string {
  const minutes = Math.round(ms / 1000 / 60);
  if (minutes < 60) return `${Math.max(1, minutes)}m`;
  const hours = Math.round(Math.floor(ms / MINUTE) / 60);
  if (hours < 24) return `${hours}h`;
  const days = Math.round(Math.floor(ms / 3_600_000) / 24);
  if (days < 30) return `${days}d`;
  if (days < 365) return `${Math.round(days / 30)}mo`;
  const years = days / 365;
  return `${years.toFixed(years < 10 ? 1 : 0)}y`;
}

// --- conversions to and from the stored row fields (validators.ts) ---

type CardFields = {
  fsrsState?: number | null;
  fsrsStep?: number | null;
  fsrsStability?: number | null;
  fsrsDifficulty?: number | null;
  lastReviewedAt?: string | null;
  nextDueAt?: string | null;
};

export function cardFromRow(row: CardFields): SrsCard | null {
  if (row.fsrsState == null || row.nextDueAt == null) return null;
  return {
    state: row.fsrsState,
    step: row.fsrsStep ?? null,
    stability: row.fsrsStability ?? null,
    difficulty: row.fsrsDifficulty ?? null,
    due: Date.parse(row.nextDueAt),
    lastReview: row.lastReviewedAt == null ? null : Date.parse(row.lastReviewedAt),
  };
}

export function cardToRow(card: SrsCard) {
  return {
    fsrsState: card.state as 1 | 2 | 3,
    fsrsStep: card.step,
    fsrsStability: card.stability,
    fsrsDifficulty: card.difficulty,
    nextDueAt: new Date(card.due).toISOString(),
    lastReviewedAt: card.lastReview === null ? null : new Date(card.lastReview).toISOString(),
  };
}
