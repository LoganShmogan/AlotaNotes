import { QuizSession } from "@/components/QuizSession";
import { PageHeader } from "@/components/ui";

export const metadata = { title: "Quiz" };

export default function QuizPage() {
  return (
    <>
      <PageHeader title="Quiz" />
      <QuizSession />
    </>
  );
}
