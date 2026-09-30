---
name: research-website
description: >
  SpiderSite research mode — answer ONE question about ONE website from the site's own
  pages, and return the pages the answer came from. Use for "what does this company
  charge", "find their pricing tiers", "who wrote this article and when was it
  published", "does this site say X", "which countries do they ship to", "summarise
  their refund policy", "read this PDF and answer", "research this website", or
  "research_website". You pass a question and, optionally, a JSON Schema for the answer;
  you get a typed answer, every source page with its author and publication date as the
  page declares them, the passages the answer was built from, a check of every URL in the
  answer against the pages read, and the model's real token usage on your own SpiderGate
  credential. Honours robots.txt; reads PDFs on request. Pulling emails and phones into a
  lead list is scrape-website-extract-leads; finding businesses is scrape-google-maps;
  registry facts are lookup-company-data.
version: "0.1.0"
category: data-collection
---

# research-website

One question, one website, an answer with its sources. It reads the site; it does not
search the web, and it never writes what it reads into your leads.

```
  url + question (+ answer_schema)
      │   robots.txt first: a disallowed page is never fetched
      ▼
  DISCOVER   single   → exactly url
             seed     → url + its sitemap + its links, ranked against the question
             adaptive → the best link, one page at a time, until the question is covered
      ▼
  READ       up to max_pages pages, 1 s apart; PDFs only with include_pdfs
      ▼
  FILTER     the passages of each page that match the question
      ▼
  ANSWER     ONE call to SpiderGate on YOUR credential, at `model`
      ▼
  data.research = { answer, answer_urls, sources[], pages_read, usage, … }
```

## Approach

1. **Pick `discover`** from the table below. Most questions are `single` (you have the page)
   or `seed` (the fact is somewhere on the site).
2. **Write the question** the way the user asked it. For anything you will use as data, send an
   `answer_schema` — and put a `source_url` field on every item, so each fact carries its page.
   See `references/write-an-answer-schema.md`.
3. **Submit** — `research_website`, or the HTTP route below. You get a `job_id`, not an answer.
4. **Poll** `get_job_status` every 3–5 s, then read `get_job_results` → `data.research`.
5. **Check** four fields before you say anything (the gate below, then `references/read-the-answer.md`).
6. **Report** the answer with the sources it cites, and say plainly when the site does not say.

<HARD-GATE>
Never report a URL from a research answer — a `source_url`, a link, a "see this page" — without
reading `data.research.answer_urls` first. Every URL in `answer_urls.ungrounded` appears on NO page
the job read: it is not the address of a page read, not a link on one, and not written in one. The
model produced it; the site did not. The job still completes, `answer_schema_valid` can still be
`true` (the SHAPE is right), and nothing else in the result says so. Drop or flag every listed URL
and cite the `sources[]` entries instead. `checked: 0` means the answer had no URL in it — it is not
a clean bill for a free-text answer that names pages without linking them.
</HARD-GATE>

## Rules (Non-Negotiable)

**`answer: null` is an answer, not a failure.** It means the pages read do not contain it (a
free-text answer may say "the sources do not say" instead). Why: resubmitting the same request
returns the SAME job for 24 hours, so a retry reads nothing new. Change what is read instead —
start from the page that should hold it, or switch `single` to `seed`.

**Author and date are what the page declares — never inferred.** They come from the page's
structured data, its meta tags, a byline that links to an author page, a `<time>` element, or a
PDF's metadata. `null` means the page does not declare one. Why: filling it from the article body
or from the site's name turns "not stated" into a fabricated attribution.

**robots.txt is honoured, by RFC 9309.** A disallowed page is never fetched and is counted in
`pages_skipped_robots`. A robots.txt that answers 5xx, or cannot be reached, closes the WHOLE site;
one that answers 404 opens it. Set `respect_robots: false` only for a site the user owns or has
permission to read. Why: a job that reads no page fails with `[research_no_readable_pages]`, and
retrying it fails identically.

**Only public `http(s)` URLs.** `file:` and `raw:` URLs are refused at submit (422). An address
that resolves to a private, loopback, link-local or reserved network is refused when the job runs —
the job fails with `[unsafe_url]` — and every redirect and every request a page makes is checked the
same way. Why: these refusals are final; a variant of the same address is refused too.

**PDFs are read only when you ask.** Set `include_pdfs: true` (up to 25 MB and 200 pages each).
Without it a PDF URL is not fetched, and a `single` job on one fails saying so. Why: the refusal is
deliberate, not a broken download.

**The answer is billed as your own SpiderGate usage.** The call runs on the job's own credential at
`model` (default `spideriq/research`; your client alias `client:<brand_id>/<name>` works). `usage`
carries the provider's own token counts, and `calls: 2` means one repair call was needed. Why: a
`seed` job puts the best passages of up to `max_pages` pages (about 60,000 characters at most) into
ONE call, so the question's breadth sets the cost.

**Research never writes to your leads.** Nothing a research job reads is added to your CRM,
IDAP or lead lists. Why: an agent that expects the site's emails to appear in IDAP afterwards will
find nothing — contact extraction is `scrape-website-extract-leads`.

**An identical request within 24 hours returns the EARLIER job** (`from_cache: true` on the
submit, from `research_website` and the HTTP route alike). Why: a site that changed since is not
re-read. Reword the question to force a fresh read.

## Decision tree — pick `discover`

| The user wants… | `discover` | `max_pages` | Example |
|---|---|---|---|
| A fact on a page whose URL you have — a byline, a policy, a spec | `single` | — (always 1) | "Who wrote this post and when?" on the post URL |
| A fact that is somewhere on the site | `seed` | 5–8 | "What pricing plans are there?" on the homepage |
| A fact you reach by following links — docs, help centres | `adaptive` | 4–8 | "What is the API rate limit?" on the docs home |
| A fact inside a PDF | `single` + `include_pdfs: true` | — | "What does this report conclude?" on the PDF URL |

`seed` reads the start page, then ranks its links and up to 10 sitemap files against the question
and reads the best until `max_pages`. `adaptive` re-ranks after every page and stops early once the
question's words are covered and the last page added nothing. Both stay on the start URL's host
(`www.` or not) — a `blog.` or `docs.` subdomain is another host, so start there if the fact lives there.

## The surfaces

| | MCP | HTTP (`https://spideriq.ai/api/v1`, Bearer `client_id:api_key:api_secret`) | CLI |
|---|---|---|---|
| Submit | `research_website` (`@spideriq/mcp-leads`, `@spideriq/mcp`) | `POST /jobs/spiderSite/submit` | `spideriq jobs submit -t spiderSite -p '<payload>'` |
| Poll | `get_job_status` · `get_job_results` | `GET /jobs/{job_id}/status` · `GET /jobs/{job_id}/results` | `spideriq jobs status\|results <id>` |

The HTTP body wraps the fields in `payload`, with `mode: "research"` beside the `research` block:

```json
{"payload": {"url": "https://plausible.io/", "mode": "research",
             "research": {"question": "What pricing plans are there and what does each cost per month?",
                          "discover": "seed", "max_pages": 5,
                          "answer_schema": {"type": "object", "required": ["tiers"], "properties": {
                            "tiers": {"type": "array", "items": {"type": "object",
                              "required": ["name", "price", "source_url"], "properties": {
                                "name": {"type": "string"}, "price": {"type": "string"},
                                "source_url": {"type": "string"}}}}}}}}}
```

If your MCP server does not list `research_website`, it predates research mode: send the same
`payload` object through `submit_job` with `type: "spiderSite"` — it forwards the payload whole.

## What you get back

`GET /jobs/{job_id}/results` → `data.research` (it is `null` on every job that was not a research job):

| Field | Read it as |
|---|---|
| `answer` | Shaped by your `answer_schema`; a string without one. `null` = the sources do not say |
| `answer_schema_valid` | `false` = the answer still broke the schema after one repair call — served anyway, with `answer_schema_errors` |
| `answer_urls` | `{checked, ungrounded}` — the HARD-GATE field |
| `sources[]` | `{url, title, author, published_at, fetched_as, passages, cited}` — every page read, in reading order |
| `pages_read` · `pages_skipped_robots` · `pages_refused_unsafe` · `pages_failed` | What happened to every page it tried |
| `skipped[]` | Up to 50 `{url, reason}`: `robots_disallowed`, `robots_unreachable`, `pdf_not_requested`, `unsafe_destination`, `http_404`, … |
| `usage` | `{model, requested_model, prompt_tokens, completion_tokens, total_tokens, calls}` |
| `full_text` | Where the full text of every page read was stored (your SpiderMedia bucket), or why it was not |

`?format=md` renders the answer and its sources first; `?format=yaml` cuts tokens.

## References (loaded on demand)

- **`references/ask-a-question.md`** — Steps / Gotchas / Verify for one research job, from picking
  `discover` to the report. **Always read** before a first job.
- **`references/write-an-answer-schema.md`** — WRONG / RIGHT for the schema: `source_url`, nullable
  fields, what the API refuses at submit.
- **`references/read-the-answer.md`** — every result field, the four checks, and every failure with
  what to do about it. **Always read.**
- **`references/robots-pdfs-and-limits.md`** — robots.txt behaviour in full, PDFs, the page and size
  limits, timing, and the 24-hour duplicate window.

## Learnings

`learnings/` holds what the first live runs taught, with provenance. They are starting points, not
ground truth — confirm against the live API before relying on a number.

- `2026-09-28-an-author-is-only-what-the-page-declares` — why `author` is `null` more often than you
  expect, and the related-posts bylines that were nearly reported as the post's authors.
- `2026-09-28-null-is-an-answer-not-a-failure`
- `2026-09-28-read-is-not-cited` — five pages read, one cited: `pages_read` is not evidence.
- `2026-09-28-an-unreachable-robots-txt-closes-the-site`
- `2026-09-28-the-same-request-within-24-hours-returns-the-earlier-job`

## See also

- **scrape-website-extract-leads** — emails, phones and social profiles from a site, into your leads.
- **company-intel** and **lookup-company-data** — registry and firmographic facts about a company.
- **use-the-gateway** (`@spideriq/gateway-skills`) — your client aliases, and the traces and usage of
  the answer calls this skill makes.
