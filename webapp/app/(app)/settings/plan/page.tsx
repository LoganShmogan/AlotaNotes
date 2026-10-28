import { redirect } from "next/navigation";

// Where Stripe Checkout and the Billing Portal send the browser back to
// (backend/convex/stripeActions.ts), for the app and the web alike.
export default async function PlanReturn({ searchParams }: { searchParams: Promise<{ checkout?: string }> }) {
  const { checkout } = await searchParams;
  redirect(`/settings?section=plan${checkout ? `&checkout=${encodeURIComponent(checkout)}` : ""}`);
}
