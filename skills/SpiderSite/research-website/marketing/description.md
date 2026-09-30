## research-website

Ask one question of one website and get the answer from the site's own pages — with the pages it
came from. Backed by SpiderSite's research mode.

### What this skill does

- **Answer** (`research_website`, `POST /jobs/spiderSite/submit` with `mode: "research"`) — read
  one page, or up to 20 pages of the same site found through its links and sitemap, and answer the
  question from what they say. Send a JSON Schema and the answer comes back as data — a pricing
  table, a list of shipping countries — with a `source_url` on every item.
- **Attribute** — every page read comes back with its title, and its author and publication date
  exactly as the page declares them, plus the passages the answer was built from.
- **Check** — every URL in the answer is compared with the pages actually read, and any the site
  does not contain is listed, so an invented citation never passes as a source.
- **Account** — the answer call runs on your own SpiderGate credential, at your model or alias, and
  returns the provider's real token counts.

### How it reads

robots.txt is honoured by RFC 9309 — a disallowed page is never fetched. PDFs are read on request.
Only public addresses are fetched, pages are read at least a second apart, and nothing read is ever
written into your leads.

### Typical workflows

- **Competitor pricing** — seed the competitor's homepage with a tiers schema; get each plan, its
  price and the page it is on.
- **Article attribution** — a single-page job on a post returns who wrote it and when, as the page
  itself states.
- **Policy check** — "Do they ship to Norway?" against a shop's shipping page, answered from the
  page, or `null` when it does not say.
- **Document question** — a PDF report with `include_pdfs`, answered with the report's own metadata.
