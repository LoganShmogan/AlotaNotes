import type { AuthConfig } from "convex/server";

// Both apps sign in through the same Clerk instance, so both tokens have
// iss = the Clerk Frontend API URL and the same `subject` (the Clerk user id):
//   - the web app sends a Clerk session JWT from the "convex" JWT template
//     (aud = "convex");
//   - the Flutter app sends the OIDC ID token from its Clerk OAuth
//     application (aud = that application's client id).
// Both values are Convex environment variables (Docs/setup_guide.md).
export default {
  providers: [
    { domain: process.env.CLERK_JWT_ISSUER_DOMAIN!, applicationID: "convex" },
    { domain: process.env.CLERK_JWT_ISSUER_DOMAIN!, applicationID: process.env.CLERK_OAUTH_CLIENT_ID! },
  ],
} satisfies AuthConfig;
