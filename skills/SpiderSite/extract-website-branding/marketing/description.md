## extract-website-branding

Brand-asset extraction from a website. 1 tool — submit a URL, get back a structured brand profile.

### What this skill does

- **`extract_branding`** — accepts a URL. Returns:
  - **Color palette** — primary, secondary, accent, background, text — sampled from CSS + computed styles + image dominant-color
  - **Typography** — font families + weights used for headings vs body, with inferred role (display, ui, body)
  - **Logo** — image URL, dimensions, dominant colors, mark-vs-wordmark classification
  - **Design tokens** — border radii in use, shadow density, contrast levels — gives a quick "is this a sharp/blocky brand or a soft/rounded brand?" read
  - **Confidence** — per-field score; sites with a robust design system get high confidence, ad-hoc sites get lower

### Why a single-method skill?

The entire surface is one analysis pipeline; splitting it into "get colors", "get fonts", "get logo" would force callers to manage 5 jobs for the same site. One call, one result, easier reasoning.

### Typical workflows

- **Personalization** — agent extracts the prospect's brand, then drafts an outreach email styled with their colors/fonts (e.g. for a landing-page-as-a-service pitch).
- **Competitive design audit** — agent extracts brands of a list of competitors, looks for design patterns ("everyone in this vertical uses navy + neon green").
- **Onboarding intake** — when a new SpiderPublish brand is being set up, agent extracts the client's existing site and pre-populates the new theme with matching tokens.

### Worker

Uses Playwright + Pillow for image processing + a small ML pass for logo classification. Run on the SpiderBrowser pool.
