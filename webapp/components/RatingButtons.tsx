"use client";
import { useEffect } from "react";
import { formatInterval, previewNextDue, RATING_LABELS, RATINGS, type Rating, type SrsCard } from "@/lib/api";

/// Again / Hard / Good / Easy, each showing when it brings the item back
/// ("Good · 3d"), with [suggested] highlighted. Keys 1-4 pick one.
export function RatingButtons({
  card,
  now,
  retention,
  suggested,
  disabled,
  onRate,
}: {
  card: SrsCard;
  now: number;
  retention: number;
  suggested?: Rating;
  disabled?: boolean;
  onRate: (rating: Rating) => void;
}) {
  const preview = previewNextDue(card, now, retention);

  useEffect(() => {
    if (disabled) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.ctrlKey || e.metaKey || e.altKey) return;
      if ((e.target as HTMLElement | null)?.closest?.("input, textarea")) return;
      const rating = Number(e.key);
      if (rating >= 1 && rating <= 4) onRate(rating as Rating);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [disabled, onRate]);

  return (
    <div className="grid grid-cols-4 gap-2" role="group" aria-label="How well did you remember it?">
      {RATINGS.map((r) => (
        <button
          key={r}
          type="button"
          disabled={disabled}
          onClick={() => onRate(r)}
          data-suggested={r === suggested || undefined}
          className="flex flex-col items-center rounded-[var(--radius-control)] border border-line bg-surface px-2 py-2 font-semibold hover:bg-tint disabled:opacity-50 data-[suggested]:border-fin data-[suggested]:bg-fin data-[suggested]:text-on-fin"
        >
          {RATING_LABELS[r]}
          <span className="text-xs font-normal opacity-80">{formatInterval(preview[r] - now)}</span>
        </button>
      ))}
    </div>
  );
}
