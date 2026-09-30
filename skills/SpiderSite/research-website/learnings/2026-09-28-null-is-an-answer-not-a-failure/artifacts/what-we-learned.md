# null is an answer, not a failure

The answer call is given numbered passages from the pages read and told to answer from them only:
no outside knowledge, and `null` — or, for a free-text answer, a plain "the sources do not say" —
when they do not contain the answer.

## The measured case

| | |
|---|---|
| Start URL | `https://docs.python.org/3/library/sys.html` |
| Question | What is the default recursion limit in Python? |
| `discover` | `adaptive`, `max_pages: 3` |
| Pages read | 2 |
| Answer | "The sources do not say." |

That is the right answer. The page documents `getrecursionlimit()` and `setrecursionlimit()` but
never states the default; the only "1000"s on it are `sys.tracebacklimit`'s default and a Windows
resource id. Every model knows the number from training — and did not use it.

## What to do with a null answer

- Report it as "the N pages read do not say", and list those pages.
- Do not fill it from your own knowledge and present that as the site's answer.
- Do not resubmit the same request: within 24 hours it returns the SAME job.
- Change what is read — start on the page that should hold the answer, or use `seed` on the
  homepage — and submit that.
