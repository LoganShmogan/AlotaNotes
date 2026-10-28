import { Suspense } from "react";
import { SettingsView } from "@/components/SettingsView";
import { PageHeader, Spinner } from "@/components/ui";

export const metadata = { title: "Settings" };

export default function SettingsPage() {
  return (
    <>
      <PageHeader title="Settings" />
      <Suspense fallback={<Spinner />}>
        <SettingsView />
      </Suspense>
    </>
  );
}
