import { httpRouter } from "convex/server";
import { internal } from "./_generated/api";
import { httpAction } from "./_generated/server";

const http = httpRouter();

// Stripe's webhook endpoint: https://<deployment>.convex.site/stripe/webhook
http.route({
  path: "/stripe/webhook",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const signature = request.headers.get("stripe-signature");
    if (signature === null) return new Response("Missing Stripe-Signature", { status: 400 });
    try {
      await ctx.runAction(internal.stripeActions.handleWebhook, { body: await request.text(), signature });
    } catch (e) {
      console.error("Stripe webhook failed:", e);
      return new Response("Webhook error", { status: 400 });
    }
    return new Response(null, { status: 200 });
  }),
});

export default http;
