# Read is not cited

`sources[]` is every page the job read, in reading order. `cited: true` marks the pages the answer
says it used. On any `seed` or `adaptive` job the two differ — the job reads the best candidates it
can find, and most of them turn out not to hold the answer.

## The measured case

`discover: "seed"`, `max_pages: 5`, start `https://plausible.io/`, question "What pricing plans are
there and what does each cost per month?":

| # | Page | `cited` |
|---|---|---|
| 1 | `https://plausible.io/` | **true** — the three plans and their prices |
| 2 | `/ad-cost-calculator` | false |
| 3 | `/simple-web-analytics` | false |
| 4 | `/lightweight-web-analytics` | false |
| 5 | `/privacy-focused-web-analytics` | false |

Pages 2–5 were ranked in because their URLs and link text matched words in the question; they did
not hold the prices. The answer's three `source_url` values all pointed at page 1, which was read.

## What to do with it

- Quote the sources with `cited: true`. Say how many pages were read, but do not offer that count
  as support for the answer.
- A `source_url` in the answer is the model's claim about where a fact came from. Check it against
  `answer_urls.ungrounded` before quoting it — a URL listed there is not a page the job read.
- An answer that cites nothing (`cited` false everywhere) with a non-null value deserves a second
  look at the passages before you rely on it.
