"use client";
import { useAuth } from "@clerk/nextjs";
import { ConvexReactClient } from "convex/react";
import { ConvexProviderWithClerk } from "convex/react-clerk";

// Sends the Clerk session's "convex" JWT with every Convex call
// (backend/convex/auth.config.ts accepts it).
const convex = new ConvexReactClient(process.env.NEXT_PUBLIC_CONVEX_URL ?? "https://missing-convex-url.convex.cloud");

export function ConvexClientProvider({ children }: { children: React.ReactNode }) {
  return (
    <ConvexProviderWithClerk client={convex} useAuth={useAuth}>
      {children}
    </ConvexProviderWithClerk>
  );
}
