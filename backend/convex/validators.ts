// Validators for the synced tables. Each table's `data` mirrors one row of
// the Flutter app's local SQLite table (lib/storage/db.dart), in camelCase,
// with two differences:
//   - parent foreign keys are the parent's client-generated `uid`, not the
//     local integer id;
//   - 0/1 flags are booleans.
// Domain timestamps stay ISO-8601 UTC strings, exactly as stored locally.
// Sync metadata (`updatedAt`, `deletedAt`) is milliseconds since the epoch.
import { v, type Infer } from "convex/values";

// Accepts a missing field or an explicit null, so the Dart client can send
// its nullable columns as they are.
const nullable = <T extends Parameters<typeof v.optional>[0]>(validator: T) =>
  v.optional(v.union(validator, v.null()));

const rating = v.union(v.literal(1), v.literal(2), v.literal(3), v.literal(4));

// The FSRS card columns shared by questions and problems.
const srsCard = {
  fsrsState: nullable(v.union(v.literal(1), v.literal(2), v.literal(3))),
  fsrsStep: nullable(v.number()),
  fsrsStability: nullable(v.number()),
  fsrsDifficulty: nullable(v.number()),
  lastReviewedAt: nullable(v.string()),
};

export const folderData = v.object({
  parentFolderUid: nullable(v.string()),
  name: v.string(),
  createdAt: v.string(),
});

export const noteData = v.object({
  folderUid: v.string(),
  title: v.string(),
  body: v.string(),
  sourceFilename: nullable(v.string()),
  sortOrder: v.number(),
  createdAt: v.string(),
  updatedAt: v.string(),
});

export const questionData = v.object({
  noteUid: v.string(),
  questionType: v.union(v.literal("short_answer"), v.literal("multiple_choice")),
  prompt: v.string(),
  expectedAnswer: v.string(),
  ...srsCard,
  nextDueAt: v.string(),
  createdAt: v.string(),
  active: v.boolean(),
  isManuallyEdited: v.boolean(),
});

export const questionChoiceData = v.object({
  questionUid: v.string(),
  choiceText: v.string(),
  isCorrect: v.boolean(),
  sortOrder: v.number(),
});

export const questionHistoryData = v.object({
  questionUid: v.string(),
  askedAt: v.string(),
  givenAnswer: v.string(),
  isCorrect: v.boolean(),
  rating,
  gradingMethod: v.union(v.literal("exact_match"), v.literal("keyword_match"), v.literal("mcq_exact")),
  nextDueAfter: v.string(),
  stabilityAfter: nullable(v.number()),
});

export const problemData = v.object({
  title: v.string(),
  url: nullable(v.string()),
  platform: v.string(),
  difficulty: v.union(v.literal("easy"), v.literal("medium"), v.literal("hard")),
  tags: v.string(),
  solution: v.string(),
  notes: v.string(),
  ...srsCard,
  // Null until the first attempt, so an untried problem is never due.
  nextDueAt: nullable(v.string()),
  createdAt: v.string(),
  updatedAt: v.string(),
});

export const problemAttemptData = v.object({
  problemUid: v.string(),
  attemptedAt: v.string(),
  solved: v.boolean(),
  durationMinutes: nullable(v.number()),
  rating,
  notes: v.string(),
  nextDueAfter: v.string(),
  stabilityAfter: nullable(v.number()),
});

export const syncedTables = {
  folders: folderData,
  notes: noteData,
  questions: questionData,
  questionChoices: questionChoiceData,
  questionHistory: questionHistoryData,
  problems: problemData,
  problemAttempts: problemAttemptData,
};

export type SyncedTable = keyof typeof syncedTables;

export const syncedTableNames = Object.keys(syncedTables) as SyncedTable[];

// History rows are written once and never edited, only deleted (when their
// parent card is), so they can't conflict.
export const appendOnlyTables: ReadonlySet<SyncedTable> = new Set(["questionHistory", "problemAttempts"]);

// One row as the client pushes it. `data` may be omitted on a tombstone.
export const pushRow = <T extends Parameters<typeof v.optional>[0]>(data: T) =>
  v.object({
    uid: v.string(),
    updatedAt: v.number(),
    deletedAt: nullable(v.number()),
    data: nullable(data),
  });

export type SyncedData = { [T in SyncedTable]: Infer<(typeof syncedTables)[T]> };
