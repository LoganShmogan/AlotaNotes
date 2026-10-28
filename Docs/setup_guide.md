# Setup guide: Convex, Clerk, Stripe and Anthropic

These are the steps that need a person with accounts. Until they're done,
the backend runs on a local anonymous Convex deployment and all its tests
pass with fakes (see `backend.md`). Do them in order: Convex first, because
Clerk and Stripe both need its URLs.

This guide covers the backend (Phase 2) and the Flutter app (Phase 3).
Phase 4 adds the web app's settings.

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
   - Redirect URIs: `com.savepoint.quillfin://callback` (Android and iOS)
     and `http://127.0.0.1:47615/callback` (Windows, Linux and macOS: the
     app listens there only while signing in).

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

## 6. The Flutter app

1. Copy `config/example.json` to `config/dev.json` (git-ignored) and fill
   it in:
   - `QUILLFIN_CLERK_DOMAIN`: the Frontend API host from step 2.2, without
     `https://`.
   - `QUILLFIN_CLERK_CLIENT_ID`: the OAuth client id from step 2.3.
   - `QUILLFIN_CONVEX_URL`: the deployment URL from step 1.3.
   - `QUILLFIN_SITE_URL`: the web app's URL.

   These are all publishable values. Keys and secrets stay in Convex.
2. Run with `flutter run --dart-define-from-file=config/dev.json`. Release
   builds take the same flag.
3. Check, on the first real sign-in:
   - The browser opens Clerk, and after signing in the app moves on by
     itself. On desktop, the tab says "You're signed in to QuillFin".
   - Settings > Sync reaches "Last synced just now", and a note made on a
     second device shows up after **Sync now**.
   - Leave the app signed in for more than an hour (Clerk ID tokens are
     short-lived), then sync again. This checks that Clerk's refresh grant
     returns a new ID token. If it doesn't, sync shows "Your session has
     expired", and `lib/auth/clerk_oauth.dart` needs to request the token
     differently.
   - Settings > Plan shows Free with 0 of 20, and **Upgrade monthly** opens
     Stripe Checkout in test mode (card `4242 4242 4242 4242`). After
     paying, coming back to the app shows Pro.

## Production

`npx convex deploy` creates the production deployment, which has its own
environment variables: set them all again there, with Clerk's production
instance and Stripe's live-mode values. Never commit any of these values.
