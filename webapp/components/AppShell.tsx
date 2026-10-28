"use client";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect } from "react";
import { Lockup, Mark } from "./Brand";

export const DESTINATIONS = [
  { href: "/today", label: "Today", icon: "M4 6h16M4 12h16M4 18h10" },
  { href: "/notes", label: "Notes", icon: "M6 3h9l3 3v15H6zM9 9h6M9 13h6M9 17h4" },
  { href: "/tracker", label: "Tracker", icon: "M8 7l-5 5 5 5M16 7l5 5-5 5" },
  { href: "/account", label: "Account", icon: "M12 12a4 4 0 100-8 4 4 0 000 8zM4 21a8 8 0 0116 0" },
  { href: "/settings", label: "Settings", icon: "M12 15a3 3 0 100-6 3 3 0 000 6zM19 12l2-1-1-3-2 .5-1.5-1.5L17 5l-3-1-1 2h-2l-1-2-3 1 .5 2L6 8.5 4 8l-1 3 2 1v0l-2 1 1 3 2-.5L7.5 16 7 18l3 1 1-2h2l1 2 3-1-.5-2 1.5-1.5 2 .5 1-3z" },
] as const;

function Icon({ d }: { d: string }) {
  return (
    <svg viewBox="0 0 24 24" className="size-6" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d={d} />
    </svg>
  );
}

/// The signed-in layout (Docs/quillfin_plan.md §5): a bottom bar on phones,
/// a rail from medium (600) up, a labelled sidebar from large (1200) up.
/// Ctrl/⌘ + 1-5 switch sections, as in the app.
export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const active = (href: string) => pathname === href || pathname.startsWith(`${href}/`);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!(e.ctrlKey || e.metaKey) || e.altKey || e.shiftKey) return;
      const index = Number(e.key) - 1;
      if (index >= 0 && index < DESTINATIONS.length) {
        e.preventDefault();
        router.push(DESTINATIONS[index].href);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [router]);

  return (
    <div className="flex min-h-dvh">
      <nav aria-label="Sections" className="sticky top-0 hidden h-dvh shrink-0 flex-col gap-1 border-r border-line bg-surface p-3 sm:flex lg:w-60">
        <div className="mb-4 flex justify-center lg:justify-start lg:px-2">
          <Mark size={32} className="text-fin lg:hidden" />
          <Lockup showOwner className="hidden lg:flex" />
        </div>
        {DESTINATIONS.map((d) => (
          <Link
            key={d.href}
            href={d.href}
            aria-current={active(d.href) ? "page" : undefined}
            className="flex flex-col items-center gap-1 rounded-[var(--radius-control)] px-3 py-2 text-xs font-medium text-ink-soft hover:bg-tint aria-[current=page]:bg-tint aria-[current=page]:text-fin lg:flex-row lg:gap-3 lg:text-sm"
          >
            <Icon d={d.icon} />
            {d.label}
          </Link>
        ))}
      </nav>
      <main className="min-w-0 flex-1 px-4 pt-4 pb-24 sm:px-6 sm:pb-8">{children}</main>
      <nav aria-label="Sections" className="fixed inset-x-0 bottom-0 z-10 flex border-t border-line bg-surface pb-[env(safe-area-inset-bottom)] sm:hidden">
        {DESTINATIONS.map((d) => (
          <Link
            key={d.href}
            href={d.href}
            aria-current={active(d.href) ? "page" : undefined}
            className="flex min-h-14 flex-1 flex-col items-center justify-center gap-0.5 text-[11px] font-medium text-ink-soft aria-[current=page]:text-fin"
          >
            <Icon d={d.icon} />
            {d.label}
          </Link>
        ))}
      </nav>
    </div>
  );
}
