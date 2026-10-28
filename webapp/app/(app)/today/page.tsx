import { TodayDashboard } from "@/components/TodayDashboard";
import { PageHeader } from "@/components/ui";

export const metadata = { title: "Today" };

export default function TodayPage() {
  return (
    <>
      <PageHeader title="Today" />
      <TodayDashboard />
    </>
  );
}
