import path from "node:path";
import type { NextConfig } from "next";

const root = path.join(import.meta.dirname, "..");

const config: NextConfig = {
  // The Convex API types and the shared FSRS and grading code come from the
  // backend workspace as TypeScript source.
  transpilePackages: ["@quillfin/backend"],
  turbopack: { root },
  outputFileTracingRoot: root,
  poweredByHeader: false,
};

export default config;
