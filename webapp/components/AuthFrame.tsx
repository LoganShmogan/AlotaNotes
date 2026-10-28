import { Lockup } from "./Brand";

/// Sign-in layout: full-screen on phones; a brand panel on the left from
/// expanded up, as in the app.
export function AuthFrame({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-dvh">
      <aside className="hidden flex-1 flex-col justify-between bg-deep p-12 text-on-deep md:flex">
        <Lockup showOwner className="[&_svg]:text-on-deep" />
        <div className="max-w-md">
          <p className="font-display text-4xl font-semibold">Remember what you learn, right before you would forget it.</p>
          <p className="mt-4 opacity-80">Notes, AI quizzes and a practice tracker, scheduled with FSRS.</p>
        </div>
      </aside>
      <main className="flex flex-1 flex-col items-center justify-center gap-8 p-6">
        <Lockup showOwner className="self-start md:hidden" />
        {children}
      </main>
    </div>
  );
}
