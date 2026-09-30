# Ask one question of one website

One research job: a start URL, a question, optionally an answer schema. This is the whole path,
from choosing where to start to what you tell the user.

## Steps

1. **Choose the start URL.** If you know which page holds the answer — the article, `/pricing`,
   `/shipping`, the PDF — start there with `discover: "single"`. If you only know the site, start
   at its homepage with `discover: "seed"`.
2. **Choose `discover`** — the table in `SKILL.md`. When in doubt between `seed` and `adaptive`:
   `seed` for a marketing site (the answer is one or two clicks from the homepage), `adaptive` for
   documentation (the answer is several links deep).
3. **Write the question as a full sentence, in the site's own words.** `seed` and `adaptive` rank
   every candidate link by the question's words appearing in its URL path and link text, so
   "What pricing plans are there and what does each cost per month?" finds `/pricing` where
   "How much?" finds nothing to rank. Common words (the, what, is — and page, site, website) are
   ignored and the rest are matched by word stem, so "plans" also matches "plan".
4. **Decide the answer's shape.** A person will read it → leave `answer_schema` out and get text.
   You will use it as data → send a schema with a `source_url` on every item
   (`references/write-an-answer-schema.md`).
5. **Submit.**

   ```
   MCP   research_website  url=https://plausible.io/
                           question="What pricing plans are there and what does each cost per month?"
                           discover=seed  max_pages=5  answer_schema={...}
   HTTP  POST /api/v1/jobs/spiderSite/submit
         {"payload": {"url": "...", "mode": "research", "research": {"question": "...", ...}}}
   ```

   The reply is a `job_id`. `from_cache: true` means an identical request in the last 24 hours
   already ran and you were handed THAT job — see the learning on duplicates.
6. **Poll** `get_job_status` every 3–5 s until `completed` or `failed`.
7. **Read** `get_job_results` → `data.research` (`format: "md"` for a person, `json` for data).
8. **Check** the four fields in `references/read-the-answer.md` — `answer_urls.ungrounded` first.
9. **Report** the answer, the sources it cites (URL, title, and author and date where the page
   declares them), and what was NOT read — pages robots.txt kept closed, pages that failed.

## Measured examples

Run on 2026-09-28 inside the worker image, against the live sites and SpiderGate. The times are
reading + answering only; a real job also waits its turn in the queue.

| Start URL | `discover` | Question | Result |
|---|---|---|---|
| `https://blog.cloudflare.com/announcing-1111/` | `single` | Who wrote this post and when was it published? | `Matthew Prince`, `2018-04-01T13:01:00.000Z` — 1 page, 1,380 tokens |
| `https://plausible.io/` | `seed`, 5 pages | What pricing plans are there and what does each cost per month? | 3 tiers, each with its `source_url` — 5 pages read, 1 cited, 14 s |
| `https://plausible.io/` | `adaptive`, 4 pages | In which country is Plausible's analytics data hosted? | `Germany` — 3 pages read, 2 cited, 7 s |
| `https://docs.python.org/3/library/sys.html` | `adaptive`, 3 pages | What is the default recursion limit in Python? | "The sources do not say." — correct: the page never states it |
| `https://www.w3.org/.../dummy.pdf` | `single` + `include_pdfs` | What text does this document contain? | `Dummy PDF file`, author from the PDF's metadata — 1 page, 388 tokens |

## Gotchas

- **`single` reads exactly one page.** Its links are not followed, whatever `max_pages` says.
- **Discovery stays on the start URL's host.** `www.` or not is the same host; `blog.` and `docs.`
  subdomains are other hosts. Start on the host that holds the answer.
- **Pages are read by a real browser**, so JavaScript-built pages work. Each page gets 30 s to load,
  and page reads are at least 1 s apart — a 20-page job spends about 20 s in pauses alone.
- **A page behind a login or a bot challenge fails to load.** It is counted in `pages_failed`, with
  its reason in `skipped[]` (e.g. `http_403`). Research reads what an anonymous visitor sees.
- **Images, video, audio, archives, fonts, scripts, style sheets, feeds, CSV and office documents are
  never candidates**, and PDFs only with `include_pdfs: true`.
- **Tracking parameters are ignored** when comparing links (`utm_*`, `fbclid`, `gclid`, …), so one
  page linked five ways is read once.

## Verify

- `data.research.pages_read` ≥ 1, and the page you expected to hold the answer is in `sources[]`.
- The source(s) the answer rests on have `cited: true`.
- `answer_urls.ungrounded` is empty — or every URL in it is dropped from what you report.
- If `pages_skipped_robots` or `pages_failed` is above 0, your report says so.
