"use client";
import { cloneElement, useEffect, useId, useRef } from "react";

type ButtonProps = React.ButtonHTMLAttributes<HTMLButtonElement> & { variant?: "primary" | "outline" | "ghost" | "danger" };

export function Button({ variant = "primary", className = "", ...props }: ButtonProps) {
  const styles = {
    primary: "bg-fin text-on-fin hover:opacity-90",
    outline: "border border-line bg-surface hover:bg-tint",
    ghost: "hover:bg-tint",
    danger: "border border-danger text-danger hover:bg-tint",
  }[variant];
  return (
    <button
      type="button"
      className={`inline-flex min-h-10 items-center justify-center gap-2 rounded-[var(--radius-control)] px-4 py-2 font-semibold transition disabled:cursor-not-allowed disabled:opacity-50 ${styles} ${className}`}
      {...props}
    />
  );
}

export function Card({ className = "", ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={`rounded-[var(--radius-card)] border border-line bg-surface p-4 ${className}`} {...props} />;
}

export function SectionLabel({ children }: { children: React.ReactNode }) {
  return <h2 className="mt-6 mb-2 text-xs font-semibold tracking-wider text-ink-soft uppercase">{children}</h2>;
}

export function EmptyState({ title, children }: { title: string; children?: React.ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-2 py-12 text-center text-ink-soft">
      <p className="font-display text-lg text-ink">{title}</p>
      {children}
    </div>
  );
}

export function Spinner({ label = "Loading" }: { label?: string }) {
  return (
    <div role="status" aria-label={label} className="flex justify-center py-12">
      <div className="size-6 animate-spin rounded-full border-2 border-line border-t-fin" />
    </div>
  );
}

export function ErrorText({ children }: { children: React.ReactNode }) {
  return children ? (
    <p role="alert" className="text-sm text-danger">
      {children}
    </p>
  ) : null;
}

/// A labelled form control. The hint sits outside the label (and is linked
/// with aria-describedby), so it isn't read as part of the field's name.
export function Field({ label, children, hint }: { label: string; children: React.ReactElement<{ "aria-describedby"?: string }>; hint?: string }) {
  const hintId = useId();
  return (
    <div className="flex flex-col gap-1">
      <label className="flex flex-col gap-1 text-sm font-medium">
        {label}
        {hint ? cloneElement(children, { "aria-describedby": hintId }) : children}
      </label>
      {hint && (
        <span id={hintId} className="text-xs text-ink-soft">
          {hint}
        </span>
      )}
    </div>
  );
}

export const inputClass =
  "w-full rounded-[var(--radius-control)] border border-line bg-surface px-3 py-2 font-normal text-ink outline-none focus:border-fin";

/// A modal dialog (the native <dialog>, so focus and Esc are handled).
export function Dialog({ open, onClose, title, children }: { open: boolean; onClose: () => void; title: string; children: React.ReactNode }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    // jsdom (tests) has no showModal; a plain open attribute stands in.
    if (open && !dialog.open) {
      if (typeof dialog.showModal === "function") dialog.showModal();
      else dialog.setAttribute("open", "");
    }
    if (!open && dialog.open) {
      if (typeof dialog.close === "function") dialog.close();
      else dialog.removeAttribute("open");
    }
  }, [open]);
  return (
    <dialog
      ref={ref}
      onClose={onClose}
      aria-label={title}
      className="m-auto w-[min(32rem,calc(100vw-2rem))] rounded-[var(--radius-card)] border border-line bg-surface p-0 text-ink backdrop:bg-black/40"
    >
      {open && (
        <div className="flex flex-col gap-4 p-5">
          <h2 className="text-lg font-semibold">{title}</h2>
          {children}
        </div>
      )}
    </dialog>
  );
}

export function Pill({ children, tone = "neutral" }: { children: React.ReactNode; tone?: "neutral" | "easy" | "medium" | "hard" | "due" }) {
  const styles = {
    neutral: "bg-tint text-ink-soft",
    easy: "bg-tint text-success",
    medium: "bg-tint text-quill",
    hard: "bg-tint text-danger",
    due: "bg-quill text-[#12212E]",
  }[tone];
  return <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-semibold ${styles}`}>{children}</span>;
}

export function PageHeader({ title, actions }: { title: string; actions?: React.ReactNode }) {
  return (
    <header className="mb-4 flex items-center justify-between gap-2">
      <h1 className="text-2xl font-semibold">{title}</h1>
      {actions && <div className="flex gap-2">{actions}</div>}
    </header>
  );
}
