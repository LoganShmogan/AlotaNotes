// Every plan limit and sync limit lives here, so pricing changes are a
// one-file edit. Prices themselves live in Stripe; the price ids reach the
// backend as environment variables (see Docs/setup_guide.md).

export type PlanId = "free" | "pro";

export const PLANS: Record<PlanId, { name: string; aiNotesPerMonth: number }> = {
  free: { name: "Free", aiNotesPerMonth: 20 },
  pro: { name: "Pro", aiNotesPerMonth: 500 },
};

export const SYNC_LIMITS = {
  // A note body is measured in UTF-8 bytes.
  maxNoteBytes: 200 * 1024,
  // Live (not deleted) rows per user per table.
  maxRowsPerTable: 50_000,
  maxRowsPerPush: 200,
  defaultRowsPerPull: 200,
  maxRowsPerPull: 500,
};

export const AI_LIMITS = {
  maxQuestionsPerRequest: 20,
  // Characters of note text sent to the model.
  maxNoteChars: 60_000,
  maxLinkedNotes: 5,
};

// Stripe subscription statuses that grant Pro. "past_due" keeps Pro while
// Stripe retries the card; Stripe moves the subscription to "canceled" or
// "unpaid" if the retries fail.
const PRO_STATUSES = new Set(["active", "trialing", "past_due"]);

export function isProStatus(status: string): boolean {
  return PRO_STATUSES.has(status);
}

// The usage period a timestamp falls in: its UTC calendar month, "YYYY-MM".
export function usagePeriod(now: number): string {
  return new Date(now).toISOString().slice(0, 7);
}
