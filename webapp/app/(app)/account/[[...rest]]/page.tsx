import { UserProfile } from "@clerk/nextjs";
import { PageHeader } from "@/components/ui";

export const metadata = { title: "Account" };

/// Clerk's account page: name, email, password, connected accounts,
/// sessions on other devices, and deleting the account.
export default function AccountPage() {
  return (
    <>
      <PageHeader title="Account" />
      <p className="mb-4 max-w-[640px] text-ink-soft">
        The same account signs you in to the QuillFin app on your phone and computer, where your notes sync and work offline.
      </p>
      <UserProfile path="/account" routing="path" />
    </>
  );
}
