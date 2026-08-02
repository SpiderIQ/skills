## company-intel

Research-grade company enrichment that goes beyond firmographics. 9 tools covering multi-source data combination, news mentions, funding events, key personnel, hiring signals, and tech stack inference.

### What this skill does

- **`research_company`** — accepts a domain or business_id, returns a comprehensive intel report:
  - Firmographics (overlap with `lookup-company-data`)
  - Recent news (last 90 days, from web search + dedicated news APIs)
  - Funding events (rounds, lead investors, valuation if disclosed)
  - Key personnel (CEO, CFO, CTO, key hires)
  - Hiring signals (open roles by department, growth trends)
  - Tech stack (frontend, backend, analytics, CRM, ad tech inferred from public signals)
  - Recent social-post highlights (LinkedIn company page)
- **`get_research`** + **`get_research_status`** — async retrieval and status.
- **`refresh_research`** — re-run for an existing business with updated sources.
- **`list_research`** + **`get_history`** — history per business across re-runs.
- **Plus 3 more diagnostic / source-control methods**

### Why this is heavier than `lookup-company-data`

`lookup-company-data` is one fast call to firmographic providers. `company-intel` is a multi-stage pipeline that runs SpiderSite + SpiderPeople + dedicated news sources in parallel and reconciles the results with cross-source confidence scoring. Slower (minutes), more expensive (multiple LLM passes for summarization), but the output is research-grade — what an SDR would produce in 30 minutes of Google searching, in one tool call.

### Typical workflows

- **Pre-call research** — agent runs `research_company` 1 hour before a sales call, drafts a one-pager for the human salesperson.
- **Account-based marketing** — agent runs `research_company` weekly on every named account, surfaces signals (new funding, key hire, news) that warrant outreach.
- **Investment screening** — VC/PE-style use case, agent runs intel reports on a list of targets.

### Cost

Significantly higher than the other lead-gen skills. Brands typically reserve `company-intel` for high-value targets, not bulk runs.
