# recipes/integrations/stripe/pricing-table

Build a `pricing_table` block from Stripe's `/v1/prices` catalog — one source of truth for price + currency, no manual page editing when the price changes.

## When to use

- The tenant prices change quarterly (SaaS subscriptions) — sync from Stripe so the page never lies.
- Multi-currency pricing (`unit_amount` per currency from Stripe) — pull the right currency for the right region.
- "Most popular" / "annual discount" badges driven by Stripe metadata.
- Pattern: "Stripe is the price book; SpiderPublish is the public catalog."

## Prerequisites

- Stripe secret key (`sk_live_...` or `sk_test_...`) with `prices:read` scope.
- A SpiderPublish PAT scoped to the tenant.
- A target page (`page_id`) where the pricing table will live.
- Decided UX: vertical (3 columns) vs horizontal (rows) — affects which `pricing_table` variant to use.

## Step 1 — Pull from Stripe

```python
import stripe
stripe.api_key = "sk_live_..."

# List active prices, expanding product for name + description
prices = stripe.Price.list(
    active=True,
    expand=["data.product"],
    limit=100
).data

# Filter to display-eligible (e.g. exclude one-off addon prices)
display_prices = [
    p for p in prices
    if p.metadata.get("display_in_table") == "true"
]
```

Pre-tag display-eligible prices with a `display_in_table=true` metadata field in the Stripe dashboard. Avoids leaking internal-only prices to the public table.

## Step 2 — Group by product (one card per product)

```python
from collections import defaultdict

cards = defaultdict(lambda: {"name": "", "description": "", "prices": []})

for price in display_prices:
    product = price.product
    cards[product.id]["name"]        = product.name
    cards[product.id]["description"] = product.description or ""
    cards[product.id]["prices"].append({
        "id":        price.id,
        "amount":    price.unit_amount / 100,                # cents → dollars
        "currency":  price.currency,
        "interval":  price.recurring.interval if price.recurring else "one_time",
        "highlight": price.metadata.get("highlight") == "true",
        "cta_text":  price.metadata.get("cta_text", "Subscribe")
    })
```

## Step 3 — Build the `pricing_table` block

```python
pricing_table_block = {
    "type": "component",
    "component_slug": "sys-pricing-table",         # or your custom slug
    "props": {
        "variant": "vertical",                       # vertical | horizontal | compact
        "show_currency_symbol": True,
        "default_interval": "month",                 # tabs between month/year if both exist
        "cards": [
            {
                "name":        c["name"],
                "description": c["description"],
                "prices":      c["prices"],
                "featured":    any(p["highlight"] for p in c["prices"])
            }
            for c in cards.values()
        ]
    }
}
```

## Step 4 — Insert or update the page

If this is a NEW pricing page:

```
content_create_page({
  title: "Pricing",
  slug:  "pricing",
  template: "default",
  blocks: [
    { type: "component", component_slug: "sys-hero-headline", props: {...} },
    pricing_table_block,
    { type: "component", component_slug: "sys-faq-accordion", props: {...} }
  ]
})
```

If the page already exists, find the existing pricing block by ID + replace it:

```python
page = content_get_page({"page_id": "<page-uuid>"})
blocks = page["blocks"]
# Find the existing pricing_table block
idx = next(i for i, b in enumerate(blocks) if b["component_slug"] == "sys-pricing-table")
blocks[idx] = pricing_table_block

content_update_page({
  "page_id": "<page-uuid>",
  "blocks":  blocks
})
```

## Step 5 — Wire CTAs to Stripe Checkout

Each price's `cta_text` button needs to land on a Stripe Checkout session. Either:

- **Static Checkout link** (low-traffic plans): pre-generate via Stripe dashboard, paste into `props.cards[*].prices[*].checkout_url`.
- **Dynamic Checkout** (most cases): set `checkout_url` to a SpiderForms submit endpoint that creates a Stripe Checkout session server-side and returns the redirect URL.

```python
# Option B: rewrite checkout_url to a SpiderForms submit
for card in pricing_table_block["props"]["cards"]:
    for price in card["prices"]:
        price["checkout_url"] = f"https://<tenant>/api/checkout?price_id={price['id']}"
```

## Step 6 — Deploy

Follow [`../../reference/deploy-protocol.md`](../../reference/deploy-protocol.md):

```
content_publish_page({ page_id })           # safe-default gated
content_deploy_site_preview()
content_deploy_site_production({ confirm_token })
```

## Steps — full flow (CI-friendly)

```python
# Run as a CI job triggered on Stripe webhook (price.created / .updated / .deleted)
1. prices = stripe.Price.list(active=True, expand=["data.product"])
2. cards  = group_by_product(filter_display_eligible(prices))
3. block  = build_pricing_table_block(cards)
4. page   = content_get_page({"page_id": "..."})
5. blocks = replace_pricing_block(page["blocks"], block)
6. content_update_page({"page_id": "...", "blocks": blocks})
7. content_publish_page({"page_id": "..."})         # via preview+confirm
8. content_deploy_site_production({confirm_token})  # via preview+confirm
```

For low-traffic pages, run this nightly instead of webhook-triggered.

## Gotchas

- **Stripe `unit_amount` is in CENTS** (or smallest currency unit). Always divide by 100 (or by the currency's decimal_digits) before passing to the table.
- **Multi-currency requires care.** A `prices.list` call returns ALL currencies. If you want only USD, filter `if price.currency == "usd"`. If you want region-aware display, the page needs client-side currency detection (out of scope here).
- **`product.description` may be Markdown.** SpiderPublish components render as HTML — escape if you can't trust the source, or use a `rich_text` rendering hint in the props_schema.
- **Stripe rate-limits at 100 req/sec.** Reasonable for catalog reads; if you're pulling 500+ prices on every page load, cache.
- **Don't store the Stripe key in the page or component.** The pulled prices land in `props` (visible client-side); the SECRET key must stay server-side only.
- **Webhook-triggered sync can race.** Two webhooks firing within milliseconds can both trigger updates; use idempotency keys + serial-pull state.
- **One-time prices vs recurring** — the snippet above handles both via `price.recurring`. Verify your `pricing_table` component supports the "one-time" variant or filter to `recurring` only.

## Verify

```
content_get_page({ page_id })
# → confirm blocks[<idx>] has the new pricing_table with current prices

content_visual_check({
  page_url: "https://<tenant>/pricing",
  viewport: "desktop"
})
# → body_text_preview should contain the current prices ("$29", "$99", etc.)
```

Manually verify each Checkout CTA:

```bash
curl -sI "https://<tenant>/pricing" | grep "200"
# Then click each CTA in a real browser to confirm Stripe Checkout opens with the right price.
```

## Anti-patterns

- **Hardcoding prices in the page blocks.** Defeats the purpose of Stripe-as-source-of-truth. Re-syncs become "edit Stripe AND edit the page in two places."
- **Listing ALL Stripe prices in the table** without `display_in_table=true` filtering. Internal/test prices leak.
- **Forgetting the CTA URL rewrite to Checkout.** The table looks right but every button 404s.
- **Pulling without filtering by `active=true`.** Inactive prices leak into the table.
- **Storing the Stripe secret in `props`.** It ships to the browser. Use a webhook-triggered server-side sync; never expose the secret.
- **Re-running the sync on every page request.** Stripe rate limits; cache the result (CDN / Redis / static page rebuild on webhook).

## See also

- [`../../content/landing-page.md`](../../content/landing-page.md) — for the page that hosts the pricing table
- [`../../marketplace/browse-cro-components.md`](../../marketplace/browse-cro-components.md) — for FAQ / urgency components that pair well with pricing
- [`../../reference/block-types.md`](../../reference/block-types.md) — the `component` block schema (pricing_table is a component slug)
- [`../../reference/deploy-protocol.md`](../../reference/deploy-protocol.md) — the publish + deploy gate flow
