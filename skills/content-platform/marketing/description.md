## content-platform

The CRUD surface a human dashboard user has, exposed as 21 tool calls. Agents can list, create, update, publish, archive, and version every content type SpiderPublish supports.

### What this skill does

- **Pages** — landing pages, marketing pages, anything served from a route. Block-based editor model: each page is a list of typed blocks (hero, text, gallery, CTA, custom component) which the Liquid engine renders.
- **Posts** — blog/news entries. Same block model as pages plus tagging, author attribution, RSS-ready metadata.
- **Docs** — documentation pages with MDX-style affordances, structured into doc trees.
- **Components** — reusable UI components with Shadow DOM isolation. Versioned independently from pages — agents can roll back a component without touching the pages that use it.
- **Domains** — per-brand custom hostnames, mapped to Cloudflare custom hostnames via the SaaS API.

### Typical workflows

- "Create a 4-page launch site for the new product" → agent creates 4 pages, populates blocks, publishes.
- "Roll back the hero on /pricing to last week's version" → agent lists component versions, restores.
- "Show me every page that uses the deprecated CTA component" → agent searches by component_id.

### Auth + isolation

All calls auto-scope to the active brand via the brand binding — agents on brand A literally cannot see brand B's pages. Two-step preview/confirm by default for destructive ops (delete, archive); first call returns a `confirm_token`, second consumes it.
