import { ConvexError } from "convex/values";

/// What to tell the user about a failed call: the backend's own message
/// for a ConvexError (e.g. AI_LIMIT_REACHED), or a generic one.
export function messageOf(error: unknown): string {
  if (error instanceof ConvexError) {
    const data = error.data as { message?: string } | string;
    if (typeof data === "string") return data;
    if (data?.message) return data.message;
  }
  return "Something went wrong. Try again.";
}

export function codeOf(error: unknown): string | null {
  if (error instanceof ConvexError && typeof error.data === "object" && error.data !== null) {
    return (error.data as { code?: string }).code ?? null;
  }
  return null;
}
