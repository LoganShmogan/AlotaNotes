# Setup guide: Convex, Clerk, Stripe and Anthropic

These are the steps that need a person with accounts. Until they're done,
the backend runs on a local anonymous Convex deployment and all its tests
pass with fakes (see `backend.md`). Do them in order: Convex first, because
Clerk and Stripe both need its URLs.

This guide covers the backend (Phase 2). Phases 3 and 4 add the Flutter and
web app settings.

## 1. Convex

1. Create an account at convex.dev.
2. In `backend/`, run `npx convex dev`. Choose to create a new project
   named `quillfin`. This writes `backend/.env.local`, which is ignored by
   git, and replaces the anonymous local deployment.
3. Note the two URLs it prints, or find them in the dashboard under
   Settings > URL & deploy key:
   - the **deployment URL**, `https://<name>.convex.cloud`, which the apps
     call;
   - the **site URL**, `https://<name>.convex.site`, which receives
     webhooks.

The first push fails until step 2.4 sets the Clerk variables. That's
expected.

## 2. Clerk

1. Create an application at clerk.com named QuillFin. Choose the sign-in
   methods you want, such as email and Google.
2. **For the web app**: go to Configure > JWT templates > New template >
   **Convex**. Keep the name `convex`. Copy the **Issuer** URL; this is
   your Clerk Frontend API URL.
3. **For the Flutter app**: go to Configure > OAuth applications > Add.
   - Name: QuillFin app.
   - Make it a **public** client (PKCE, no client secret).
   - Scopes: `openid profile email`.
   - Redirect URIs: `com.savepoint.quillfin://callback` and
     `http://localhost/callback` (loopback, for Windows and Linux; the
     exact loopback form is settled in Phase 3).

   Copy the **Client ID**.
4. Set both values on Convex:

   ```bash
   cd backend
   npx convex env set CLERK_JWT_ISSUER_DOMAIN https://<your-frontend-api>.clerk.accounts.dev
   npx convex env set CLERK_OAUTH_CLIENT_ID <client id>
   npx convex dev --once
   ```

## 3. Anthropic (AI generation on QuillFin's key)

1. Create an API key at console.anthropic.com, in an organisation with
   billing set up. Set a monthly spend limit there as a backstop to the
   plan limits.
2. Set it on Convex:

   ```bash
   npx convex env set ANTHROPIC_API_KEY sk-ant-...
   ```

   To use a different model than the default `claude-sonnet-5-5`, also set
   `QUILLFIN_AI_MODEL`.

## 4. Stripe

Do this in **test mode** first. Repeat it in live mode before launch.

1. Create a product, **QuillFin Pro**, with two recurring prices: monthly
   and yearly. Copy both price ids (`price_…`).
2. Go to Settings > Billing > Customer portal and turn it on. Allow
   cancelling and switching between the two prices.
3. Go to Developers > Webhooks > Add endpoint.
   - URL: `https://<name>.convex.site/stripe/webhook` (the **site** URL).
   - Events: `checkout.session.completed`,
     `customer.subscription.created`, `customer.subscription.updated`,
     `customer.subscription.deleted`, `customer.subscription.paused`,
     `customer.subscription.resumed`.

   Copy the signing secret (`whsec_…`).
4. Set everything on Convex. `SITE_URL` is where the web app will live;
   Checkout returns there.

   ```bash
   npx convex env set STRIPE_SECRET_KEY sk_test_...
   npx convex env set STRIPE_WEBHOOK_SECRET whsec_...
   npx convex env set STRIPE_PRICE_PRO_MONTHLY price_...
   npx convex env set STRIPE_PRICE_PRO_YEARLY price_...
   npx convex env set SITE_URL https://quillfin.app
   ```

## 5. Check it

- In the Convex dashboard, Functions should list `sync`, `billing`, `ai`
  and `stripeActions`. Settings > Environment variables should list
  everything above.
- Under Stripe > Webhooks > your endpoint, use "Send test webhook" with
  `customer.subscription.updated`. It answers 200; the subscription is
  ignored because it belongs to no QuillFin user, and the Convex logs say
  so.
- The end-to-end check (sign in, upgrade, sync) needs the apps from
  Phases 3 and 4.

## Production

`npx convex deploy` creates the production deployment, which has its own
environment variables: set them all again there, with Clerk's production
instance and Stripe's live-mode values. Never commit any of these values.
