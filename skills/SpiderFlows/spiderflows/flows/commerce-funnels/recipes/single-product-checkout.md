# Single-product checkout funnel

The simplest commerce funnel: one product, one checkout, one thank-you. No upsell.

```
checkout node → thank-you
```

## Build

```
funnel_template_apply { slug: "single-product-checkout", name: "<product> checkout <date>" }
# → DRAFT flow, kind="funnel", one checkout node + thank-you. Capture flow_id.

flow_update_node { flow_id, node_id, ... }   # customise the checkout page copy
```

Uses the product seeded in the template's Medusa catalog (create new products in Medusa Admin —
the agent-native product surface is [8.6c]).

## Publish + verify

```
# publish with live_mode=true (NOT a status flip)
content_visual_check { page_url: "/f/<flow_id>", expected_no_text: ["couldn't load"] }
```

## Walk + read

Complete checkout with Stripe TEST card `4242 4242 4242 4242`. A succeeded PaymentIntent writes a
`commerce_orders` row and fires `commerce.order_placed`.

```
commerce_order_list { status: "succeeded" }
```

Confirm the email via `notification_log channel='email' status='sent'` — never `mail_messages`.

Pairs with: [build-tripwire-oto.md](build-tripwire-oto.md) · [read-orders.md](read-orders.md)
