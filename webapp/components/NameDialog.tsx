"use client";
import { useState } from "react";
import { messageOf } from "@/lib/errors";
import { Button, Dialog, ErrorText, inputClass } from "./ui";

/// Asks for a name (a new folder, a renamed one, a new note's title).
export function NameDialog({
  open,
  title,
  label,
  initial = "",
  submitLabel = "Save",
  onClose,
  onSubmit,
}: {
  open: boolean;
  title: string;
  label: string;
  initial?: string;
  submitLabel?: string;
  onClose: () => void;
  onSubmit: (name: string) => Promise<void>;
}) {
  const [name, setName] = useState(initial);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  return (
    <Dialog open={open} onClose={onClose} title={title}>
      <form
        className="flex flex-col gap-4"
        onSubmit={async (e) => {
          e.preventDefault();
          if (name.trim() === "") return setError(`${label} can't be empty.`);
          setBusy(true);
          try {
            await onSubmit(name.trim());
            setName("");
            onClose();
          } catch (err) {
            setError(messageOf(err));
          } finally {
            setBusy(false);
          }
        }}
      >
        <input aria-label={label} autoFocus className={inputClass} value={name} onChange={(e) => setName(e.target.value)} />
        <ErrorText>{error}</ErrorText>
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" disabled={busy}>
            {submitLabel}
          </Button>
        </div>
      </form>
    </Dialog>
  );
}
