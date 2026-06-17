# SpiderPublish — author, publish, and deploy a brand's site

One skill for the whole SpiderPublish content surface. An agent can stand up and
run a brand's website end-to-end without leaving the conversation:

- **Pages & blog** — block-based pages, blog posts (authors, tags, categories,
  cover images, featured), docs trees. Body is Tiptap JSON; the renderer turns it
  into a live site.
- **Components & themes** — reusable Shadow-DOM components, the global section
  marketplace, pre-built themes, curated starter sites, and per-tenant Liquid
  template overrides.
- **Navigation, settings, media, domains** — header/footer menus, SEO + analytics
  settings, first-party CDN media hosting, and custom-domain onboarding.
- **Safe deploy** — two-phase preview → confirm before anything reaches the
  Cloudflare edge (~2–5s), so production changes are never a surprise.

Per-tenant and PAT-scoped, with the five-lock tenant defense underneath. The skill
teaches the one thing generic CMS knowledge gets wrong: **authoring is not live —
publish flips a flag, deploy pushes the edge.**
