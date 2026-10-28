/// The QuillFin mark: a quill nib whose feather sweeps into a fin. Same
/// geometry as public/quillfin-mark.svg and the app's QuillFinMark.
export function Mark({ size = 28, className = "text-fin" }: { size?: number; className?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" aria-hidden className={className}>
      <path fill="currentColor" d="M12 54C12 32 28 12 54 8C52 22 46 32 36 38L42 40C34 48 24 52 12 54Z" />
    </svg>
  );
}

export function Lockup({ showOwner = false, className = "" }: { showOwner?: boolean; className?: string }) {
  return (
    <div className={`flex items-center gap-2 ${className}`}>
      <Mark />
      <div className="leading-tight">
        <div className="font-display text-xl font-semibold">QuillFin</div>
        {showOwner && <div className="text-xs opacity-75">by Save Point</div>}
      </div>
    </div>
  );
}
