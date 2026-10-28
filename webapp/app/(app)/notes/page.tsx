import { Suspense } from "react";
import { NotesWorkspace } from "@/components/NotesWorkspace";
import { PageHeader, Spinner } from "@/components/ui";

export const metadata = { title: "Notes" };

export default function NotesPage() {
  return (
    <>
      <PageHeader title="Notes" />
      <Suspense fallback={<Spinner />}>
        <NotesWorkspace />
      </Suspense>
    </>
  );
}
