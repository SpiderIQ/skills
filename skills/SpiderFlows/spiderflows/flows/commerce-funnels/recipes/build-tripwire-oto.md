# Build a tripwire + OTO commerce funnel

A **commerce funnel** is a kind of Flow that sells a product: a low-priced *tripwire*
checkout, then a *one-time offer* (OTO) upsell, then thank-you. You don't build the graph
by hand — you **fork a template** and customise it.

```
flow:commerce  (kind='funnel' carrying checkout + oto nodes)
checkout node → oto node → thank-you
(tripwire buy)  (accept = charge upsell off-session · decline = no-op)  (order placed)
```

## The create-path: `funnel_template_apply`, NEVER raw `flow_create`

Commerce graphs have invariants the mutation-time validator enforces (`OTO_REQUIRES_CHECKOUT`,
`COMMERCE_NODE_LAYER`). Hand-building one with `flow_create` + `flow_add_node` will fight the
validator. **Always fork a starter:**

```
funnel_template_list { kind: "commerce" }
# → single-product-checkout · tripwire-oto · subscription-checkout

funnel_template_apply { slug: "tripwire-oto", name: "Spring tripwire <date>" }
# → a NEW DRAFT flow in your tenant: kind="funnel", checkout + oto nodes wired,
#   seed pages forked into your content_pages. Capture flow_id.
```

The forked flow uses the **products already in the template's Medusa catalog**. You cannot create
a commerce *product* through MCP/CLI yet — product creation is the Medusa Admin UI today (the
[8.6c] gap). Customise copy/offers/upsell wiring; create new products in Medusa Admin.

## Customise

Edit a node's page copy or the offer with `flow_update_node`. Add or retune routing with
`flow_add_edge` / `flow_update_edge`:

```
flow_get { flow_id }                          # inspect nodes + edges
flow_update_node { flow_id, node_id, ... }    # change checkout/oto copy
```

**Edge operators are LONG-FORM.** Use `op: "equal"` (or `not_equal`, `greater_than`, …).
`op: "eq"` is NOT a recognised token — `compare_leaf` has no `eq` alias, so the edge silently
**never matches** and the buyer is never routed. (This was the 8.T1 production bug.)

## Publish — `live_mode=true`, NOT a status flip

```
# Publish the funnel for real traffic:
#   live_mode=true   (this is the publish switch — NOT a status='active' flip)
```

After publish, verify the rendered page with `content_visual_check` against `/f/<flow_id>`
(`expected_no_text: ["couldn't load"]`).

## Walk the buyer path (Stripe TEST)

In test mode use card `4242 4242 4242 4242`, any future expiry, any CVC. Complete the checkout,
then at the OTO step:

- **accept** → the upsell is charged **off-session** against the saved PaymentIntent, then routes
  to thank-you.
- **decline** → a no-op; also routes to thank-you (no charge).

Both clicks route to thank-you and **neither 500s** (the engine has a defensive `resolve()` guard
since 8.T1-fix). The OTO charge fires *before* edge evaluation, so a malformed edge used to charge
then crash — that class is closed.

## Read the orders

A completed checkout writes a **Stripe-canonical order** (`commerce_orders`) — Stripe is the
order-of-record, Medusa is catalog/cart only. Read them:

```
commerce_order_list { status: "succeeded" }     # paginated; status / contact_email / since filters
commerce_order_get { order_id }                  # line items, customer, PaymentIntent, lifecycle
commerce_order_stats { window: "30d" }           # revenue, orders, success rate, AOV
commerce_order_export_csv { ... }                # client-side CSV over the list
```

CLI: `spideriq commerce orders list|get|stats|export`. The order surface is **read-only** by
design — orders are written server-side on a succeeded Stripe PaymentIntent; there is no
create/update/delete.

## Notifications

A sale fires `commerce.order_placed` (email + bell). To confirm an email actually sent, check
`notification_log channel='email' status='sent'` — **never `mail_messages`** (that's the SpiderMail
inbox store, a different surface). `flow.run_completed` and `flow.run_abandoned` also fire for
funnel runs.

## What's NOT shipped (don't promise it)

- **Refunds / disputes** — order observability is forward-only today; the Stripe webhook receiver
  is [8.4b], not yet shipped.
- **Product authoring** — Medusa Admin UI only ([8.6c]).
- **Post-order enrichment** (auto SpiderVerify/SpiderPeople on a buyer) — [8.4c].

## Anti-patterns

- ❌ `flow_create` + hand-wired checkout/oto nodes → fights the validator. ✅ `funnel_template_apply`.
- ❌ `op: "eq"` on an edge → silent non-match. ✅ `op: "equal"`.
- ❌ Flipping `status` to publish. ✅ `live_mode=true`.
- ❌ Checking a sent email via `mail_messages`. ✅ `notification_log channel='email' status='sent'`.
- ❌ Telling the user product creation is agent-native. ✅ It's Medusa Admin until [8.6c].

Pairs with: [single-product-checkout.md](single-product-checkout.md) · [subscription-checkout.md](subscription-checkout.md) · [read-orders.md](read-orders.md)
