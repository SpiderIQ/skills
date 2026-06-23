## capture-landing-page

Landing-page snapshot + conversion-tracking metadata. 3 tool calls — submit, results, list.

### What this skill does

- **`submit_landing_capture`** — accepts a URL + optional viewport configs (mobile/desktop/tablet). Returns `job_id`.
- **`get_landing_results`** — full-page screenshots per viewport, plus extracted metadata: headline, primary CTA text + position, form-field count, page weight, load time, presence of trust signals (testimonials, social proof, badges).
- **`list_landings`** — history.

### Why this matters for lead-gen

When pursuing competitive intelligence — "what does this competitor's landing page look like, what's their primary CTA, are they running A/B tests?" — capture-landing-page is the right starting point.

For outreach personalization — "I noticed your landing page has a calculator at the top — we built one too, here's how ours compares" — agents extract the page asset + metadata in one call.

### Architecture

SpiderLanding worker uses Playwright + the SpiderBrowser pool. Screenshots saved to SpiderMedia (per-brand isolation). Metadata extraction is a hybrid of CSS-selector heuristics (for layout) + LLM-based extraction (`spideriq/classification` task alias) for headline/CTA/trust-signal classification.

### Typical workflows

- **Competitive scan** — agent captures a competitor's landing page weekly, diffs against the prior week, flags significant changes.
- **Outreach personalization** — agent captures the prospect's landing page right before drafting outreach, references something specific from the page.
- **Conversion audit** — agent captures multiple competitor pages in the same vertical, surfaces patterns (everyone uses a calculator, everyone shows G2 logos at top).
