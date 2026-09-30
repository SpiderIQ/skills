# robots.txt, PDFs and limits

The rules that decide what a research job may read, and how much.

## robots.txt (RFC 9309)

Before reading anything, the job fetches the start host's `/robots.txt`. The rules for the
`SpiderIQ` user agent apply, or the `*` group when there is none for it.

| robots.txt answers | `robots.policy` | Effect |
|---|---|---|
| 2xx | `parsed` | Each page is checked against the rules; a disallowed page is never fetched |
| 4xx (404, 403, …) | `allow_all` | No rules — the whole host may be read |
| 5xx, a timeout, or no answer | `disallow_all` | The whole host is closed — nothing is read |
| — (`respect_robots: false`) | `ignored` | robots.txt is not even requested |

**WRONG** — reading `[research_no_readable_pages] … 1 disallowed by robots.txt` as a transient error
and resubmitting. **RIGHT** — the site's rules said no; the same request fails the same way (and
within 24 hours returns the same job). Start on a page the rules allow, or, for a site the user owns
or has permission to read, set `respect_robots: false`.

**WRONG** — assuming a site is closed because its robots.txt 404s. **RIGHT** — a 404 robots.txt means
"no rules": everything may be read.

The same file names the site's sitemaps (`Sitemap:` lines). `seed` reads those on the start host —
or `/sitemap.xml` and `/sitemap_index.xml` when none are named — up to 10 sitemap files of up to
10 MB each, and up to 5,000 candidate URLs in total. Sitemap files are subject to the same rules.

## PDFs

Off unless `include_pdfs: true`.

| | Without `include_pdfs` | With it |
|---|---|---|
| A PDF linked from a page | Never fetched, not a candidate | A candidate like any page |
| A PDF as the start URL | Not fetched; a `single` job fails `[research_no_readable_pages] … 1 PDF not read because PDF reading was not requested.` | Read |

A PDF is read up to 25 MB and 200 pages. Its `author` and `published_at` come from the PDF's own
metadata, and its source says `fetched_as: "pdf"`.

## Public addresses only

The start URL, every redirect, every page and PDF, and every request a page makes while loading are
checked: an address that resolves to a private, loopback, link-local or reserved network is refused
and never fetched. `file:` and `raw:` URLs, URLs with spaces, backslashes or control characters,
and URLs with no host are refused at submit (422). A refusal during the job is counted in
`pages_refused_unsafe`, or fails the job with `[unsafe_url]` when it is the start URL.

## Limits

| | Limit |
|---|---|
| `question` | 3–2,000 characters |
| `answer_schema` | ≤ 20,000 characters; local `$ref`s only |
| `max_pages` | 1–20 (default 8); `single` always reads 1 |
| `model` | ≤ 128 characters (default `spideriq/research`) |
| Page load | 30 s per page; up to 5 redirects |
| Pace | page reads at least 1 s apart |
| Passages | up to 5 per page, 1,200 characters each; about 60,000 characters in total reach the answer call — passages are trimmed from the page with the most, and no page is dropped |
| Answer | up to 4,000 tokens; at most 2 calls (1 repair) |
| `skipped[]` | the first 50 pages not read |
| `answer_urls.ungrounded` | the first 20 |
| Full text | up to 2,000,000 characters, stored only in the account's own SpiderMedia bucket |

## Duplicates

The submit is de-duplicated per workspace over the WHOLE payload for 24 hours: the same `url`,
`mode` and `research` block returns the earlier job with `from_cache: true`, whatever state it is
in. Any change — a word in the question, `max_pages`, `discover` — is a new job and a new read.
