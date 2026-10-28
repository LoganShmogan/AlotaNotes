import { afterEach, expect, test, vi } from "vitest";

afterEach(() => {
  delete process.env.CLERK_JWT_ISSUER_DOMAIN;
  delete process.env.CLERK_OAUTH_CLIENT_ID;
  vi.resetModules();
});

test("accepts the web app's Convex JWT and the Flutter app's OAuth ID token from one Clerk issuer", async () => {
  process.env.CLERK_JWT_ISSUER_DOMAIN = "https://clerk.quillfin.test";
  process.env.CLERK_OAUTH_CLIENT_ID = "oauth_client_1";
  const { default: config } = await import("../convex/auth.config");
  expect(config.providers).toEqual([
    { domain: "https://clerk.quillfin.test", applicationID: "convex" },
    { domain: "https://clerk.quillfin.test", applicationID: "oauth_client_1" },
  ]);
});
