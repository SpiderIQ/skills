# Read the answer — and every way a research job ends

`GET /jobs/{job_id}/results` returns `{success, job_id, type, status, completed_at, data, error_message}`.
A research job's findings are in `data.research`; every other SpiderSite job has `data.research: null`.

## The four checks, in order

1. **`answer_urls.ungrounded` is empty.** Each URL listed appears on no page the job read — not a
   page's address, not a link on one, not written in one. Drop it from your report or flag it as
   unverified. `answer_urls.checked` is how many URLs the answer contained; `0` means there was
   nothing to check, not that everything checked out.
2. **`answer_schema_valid` is `true`.** If `false`, `answer_schema_errors` says where the answer
   breaks your schema; use only the parts that are right.
3. **`answer` is not `null`.** `null` (or free text saying the sources do not say) means the pages
   read do not contain the answer. Report exactly that, with what was read — never fill the gap from
   your own knowledge, and never present it as the site's answer.
4. **Quote the sources with `cited: true`.** `pages_read` says how much was read, not what the answer
   rests on. Measured: a pricing question read 5 pages and cited 1.

## Every field

| Field | Meaning |
|---|---|
| `question` · `discover` | What you asked and how pages were found |
| `answer` | Shaped by `answer_schema`; a string without one; `null` = the sources do not say |
| `answer_schema_valid` · `answer_schema_errors` | Whether the answer fits the schema after at most one repair call, and up to 3 reasons if not |
| `answer_urls` | `{checked, ungrounded}` — up to 20 URLs from the answer found on no page read |
| `sources[]` | One per page read, in reading order: `url` (after redirects), `title`, `author`, `published_at`, `fetched_as` (`html` or `pdf`), `passages` (the text the answer was given, up to 5 per page), `cited` |
| `pages_read` | Pages read successfully |
| `pages_skipped_robots` | Pages robots.txt disallowed — never fetched |
| `pages_refused_unsafe` | Pages refused because their address is private or reserved — never fetched |
| `pages_failed` | Pages that did not load (timeout, `http_404`, `http_403`, an empty page, …) |
| `skipped[]` | Up to 50 `{url, reason}` for everything above that was not read |
| `robots` | `{respected, policy, note}` — `policy` is `parsed`, `allow_all` (robots.txt answered 4xx), `disallow_all` (5xx or unreachable) or `ignored` (`respect_robots: false`) |
| `usage` | `{model, requested_model, prompt_tokens, completion_tokens, total_tokens, calls}` — `model` is the provider model that answered; `requested_model` is what you sent |
| `full_text` | `{stored: true, url}` — the full text of every page read, in your SpiderMedia bucket as `research/<job_id>.md`; or `{stored: false, reason}` (`no_spidermedia_bucket` when the account has no bucket of its own) |
| `engine` · `checked_at` | Engine version and when the answer was produced (UTC) |

`author` and `published_at` are what the page declares — structured data, meta tags, a byline
linking an author page, a `<time>` element, or PDF metadata — and `null` when it declares nothing.
A page with several credited authors gives them comma-separated.

## Statuses and timing

| Status | Means |
|---|---|
| `queued` | Waiting or already running — a first attempt can read `queued` until it finishes |
| `processing` | A retry after a failed attempt |
| `completed` | `data.research` is ready |
| `failed` | `error_message` says why (below) |
| `cancelled` | Cancelled before it finished |

Reading and answering took 7–23 s for 1–5 pages in measured runs, plus the wait for a free
worker. A 20-page job takes a few minutes. Poll every 3–5 s.

## When it fails

A failed job's `error_message` starts with a `[reason]` token and one plain sentence.

| `error_message` starts with | Means | Retried automatically? | Do |
|---|---|---|---|
| `[research_no_readable_pages]` | No page could be read. The sentence counts why: disallowed by robots.txt, refused as unsafe, failed to load, PDF not requested | No | robots → start on an allowed page (or get permission); PDF → `include_pdfs: true`; failed to load → check the URL opens for an anonymous visitor |
| `[unsafe_url]` | The URL is not a public http(s) address — or resolved to a private one when fetched | No | Use the public URL; variants of the same address are refused too |
| `[research_answer_failed] SpiderGate answered HTTP 4xx` | The gateway refused the answer call — usually a `model` alias that does not exist or is not yours | No | Fix `model` (or omit it for `spideriq/research`) |
| `[research_answer_failed]` with HTTP 429 or 5xx, or "could not be reached" | The gateway was busy or down | Yes | Wait for the retry |
| `[research_unavailable]` | Research could not reach the gateway for this job | No | Report the `job_id` to support |
| `[research_input]` | The research block was malformed | No | Fix the request (the API normally refuses these at submit, with a 422) |

And refused at submit, before any job exists — **422**: see the table in
`references/write-an-answer-schema.md`.

## What to tell the user

- The answer, then the cited sources: title, URL, and the author and date where the page declares
  them.
- Anything in `answer_urls.ungrounded`, flagged as not found on the site.
- What was not read and why: "robots.txt kept 3 pages closed", "2 pages failed to load".
- For a `null` answer: "The N pages read do not say", and which pages those were.
