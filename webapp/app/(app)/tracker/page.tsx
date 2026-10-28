import { Suspense } from "react";
import { Tracker } from "@/components/Tracker";
import { PageHeader, Spinner } from "@/components/ui";

export const metadata = { title: "Tracker" };

export default function TrackerPage() {
  return (
    <>
      <PageHeader title="Tracker" />
      <Suspense fallback={<Spinner />}>
        <Tracker />
      </Suspense>
    </>
  );
}
