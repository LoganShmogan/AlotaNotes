import Link from "next/link";
import { redirect } from "next/navigation";
import { auth } from "@clerk/nextjs/server";
import { AuthFrame } from "@/components/AuthFrame";

export default async function Landing() {
  if ((await auth()).userId) redirect("/today");
  return (
    <AuthFrame>
      <div className="flex w-full max-w-sm flex-col gap-4">
        <h1 className="text-3xl font-semibold">Welcome to QuillFin</h1>
        <p className="text-ink-soft">Notes, AI quizzes and a practice tracker, each brought back right before you&apos;d forget it.</p>
        <Link href="/sign-up" className="rounded-[var(--radius-control)] bg-fin px-4 py-3 text-center font-semibold text-on-fin">
          Create an account
        </Link>
        <Link href="/sign-in" className="rounded-[var(--radius-control)] border border-line px-4 py-3 text-center font-semibold">
          Sign in
        </Link>
        <p className="text-sm text-ink-soft">The same account works in the QuillFin app on your phone and computer.</p>
      </div>
    </AuthFrame>
  );
}
