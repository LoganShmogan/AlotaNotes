"use client";
import { useAction, useQuery } from "convex/react";
import { useState } from "react";
import { api } from "@/lib/api";
import { messageOf } from "@/lib/errors";
import { formatDate } from "@/lib/time";
import { Button, Card, ErrorText, Spinner } from "./ui";

/// Settings > Plan. A live query, so it updates by itself when Stripe's
/// webhook lands after a checkout.
export function PlanPanel({ checkout }: { checkout?: string | null }) {
  const plan = useQuery(api.billing.me, {});
  const startCheckout = useAction(api.stripeActions.createCheckoutSession);
  const openPortal = useAction(api.stripeActions.createPortalSession);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  if (plan === undefined) return <Spinner />;

  const go = async (url: () => Promise<{ url: string }>) => {
    setBusy(true);
    setError(null);
    try {
      window.location.assign((await url()).url);
    } catch (e) {
      setError(messageOf(e));
      setBusy(false);
    }
  };
  const sub = plan.subscription;
  const usage = plan.aiNotes.limit === 0 ? 0 : Math.min(1, plan.aiNotes.used / plan.aiNotes.limit);

  return (
    <div className="flex flex-col gap-4">
      {checkout === "success" && !sub && <p role="status">Thanks! Your upgrade is being confirmed; this page updates on its own.</p>}
      {checkout === "success" && sub && <p role="status" className="text-success">You&apos;re on Pro. Thank you!</p>}
      <Card className="flex flex-col gap-3">
        <div>
          <p className="font-display text-xl font-semibold">QuillFin {plan.planName}</p>
          <p className="text-sm text-ink-soft">
            {sub?.currentPeriodEnd
              ? `${sub.cancelAtPeriodEnd ? "Ends" : "Renews"} on ${formatDate(new Date(sub.currentPeriodEnd).toISOString())}${!sub.cancelAtPeriodEnd && sub.interval ? ` (${sub.interval}ly)` : ""}`
              : "Pro raises the monthly allowance on QuillFin's AI."}
          </p>
        </div>
        <div>
          <p className="text-sm">
            QuillFin&apos;s AI this month: {plan.aiNotes.used} of {plan.aiNotes.limit} notes
          </p>
          <div className="mt-1 h-2 rounded-full bg-tint" role="progressbar" aria-valuenow={plan.aiNotes.used} aria-valuemax={plan.aiNotes.limit} aria-label="AI use this month">
            <div className={`h-2 rounded-full ${usage >= 1 ? "bg-danger" : "bg-fin"}`} style={{ width: `${usage * 100}%` }} />
          </div>
        </div>
        {plan.plan === "pro" ? (
          <Button variant="outline" disabled={busy} onClick={() => go(() => openPortal({}))}>
            Manage plan
          </Button>
        ) : plan.upgradeAvailable ? (
          <div className="flex flex-wrap gap-2">
            <Button disabled={busy} onClick={() => go(() => startCheckout({ interval: "month" }))}>
              Upgrade monthly
            </Button>
            <Button variant="outline" disabled={busy} onClick={() => go(() => startCheckout({ interval: "year" }))}>
              Upgrade yearly
            </Button>
          </div>
        ) : (
          <p className="text-sm text-ink-soft">Upgrades aren&apos;t open yet.</p>
        )}
        <ErrorText>{error}</ErrorText>
      </Card>
    </div>
  );
}
