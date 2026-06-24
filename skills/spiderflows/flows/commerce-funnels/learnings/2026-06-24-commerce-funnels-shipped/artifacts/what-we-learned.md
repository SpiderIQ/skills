# Commerce funnels — what we learned shipping Unified Funnels + Commerce P3

Commerce is **a kind of Flow**, not a separate product. A commerce funnel is a `kind='funnel'`
flow carrying `checkout` + `oto` nodes; it renders through the same `/f/<flow_id>` surface as every
other Flow and rides the same Redis session + event engine.

## 1. Fork a template — never hand-build the graph

The mutation-time graph validator (`validate_commerce_graph`) raises `OTO_REQUIRES_CHECKOUT` (400)
and `COMMERCE_NODE_LAYER` (400), plus Pydantic-first 422 on enum violations. Hand-wiring a commerce
graph with `flow_create` + `flow_add_node` fights all of that. The shipped create-path is
`funnel_template_apply { slug }` — it forks one of the 3 commerce starters
(`single-product-checkout`, `tripwire-oto`, `subscription-checkout`) into a tenant draft with a
valid graph + forked seed pages, then you customise with `flow_update_node`.

## 2. `op:"equal"`, never `op:"eq"` (the 8.T1 production bug)

Edge conditions go through `compare_leaf`, whose canonical operator token is `"equal"`. There is
**no `"eq"` alias and no normalization**. The flagship `tripwire-oto` seed shipped its OTO
accept/decline edges with `op:"eq"` AND scalar operands (bare strings where `{type,value}` dicts
were expected). Result: the scalar operand threw `AttributeError` → HTTP 500 at the OTO click
(after the off-session charge fired), and even once operands were fixed, `"eq"` degraded to `False`
so the edge never matched and the buyer was never routed to thank-you. The 8.T1-fix corrected the
seed AND added a defensive `resolve()` guard (non-dict operand → `None` + warning, no 500).
**Lesson: always long-form operators; the OTO charge fires before edge evaluation, so a broken edge
charges then strands.**

## 3. `live_mode=true` publishes — a `status` flip does not

Publishing a funnel for real traffic is the `live_mode=true` switch, not a `status='active'` change.

## 4. Stripe is the order-of-record

There is no Medusa order and no `order.placed` webhook (Medusa is catalog/cart only, zero
subscribers). On a succeeded Stripe `PaymentIntent`, `commerce_order_service.write_order` UPSERTs a
per-tenant `commerce_orders` row (mig 353) and fires `commerce.order_placed`. Read orders via the
4 `commerce_order_*` MCP tools / `spideriq commerce orders` CLI. Money: `total_amount_cents` is the
authoritative Stripe minor-unit figure; Medusa `unit_price` is major-unit — never mix.

## 5. Email check is `notification_log`, never `mail_messages`

To confirm a `commerce.order_placed` (or `flow.run_completed`/`flow.run_abandoned`) email actually
sent: `notification_log channel='email' status='sent'`. `mail_messages` is the SpiderMail inbox
store — a different surface that does NOT record outbound notification sends.

## 6. The honest gap — product creation is Medusa Admin only

Agents author a commerce funnel end-to-end (template → customise → publish → walk → read orders)
**except creating the product itself** — that is the Medusa Admin UI today. The agent-native
product-authoring MCP/CLI surface is carved as **[8.6c]** (the T-C12 4/6 → 6/6 gap). Do not tell a
user product creation is agent-native yet. Other carved follow-ups: [8.4b] Stripe webhook
(refunds/disputes), [8.4c] post-order enrichment.
