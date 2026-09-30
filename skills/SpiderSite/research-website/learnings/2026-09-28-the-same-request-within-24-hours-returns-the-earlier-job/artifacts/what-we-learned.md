# The same request within 24 hours returns the earlier job

Every job submission is de-duplicated per workspace, over the whole payload, for 24 hours. For a
research job the payload is the `url`, `mode: "research"` and the `research` block — every field of
it, including the defaults the API fills in.

| You submit | You get |
|---|---|
| exactly what you sent in the last 24 hours | the EARLIER job: same `job_id`, its status, later its answer — `from_cache: true` |
| anything different — one word of the question, `max_pages`, `discover`, `include_pdfs` | a new job and a fresh read |

`research_website` returns `from_cache` and, when it is `true`, a message saying this is the earlier
job and not a new read. Over HTTP it is the `from_cache` field on the submit response.

## Why it matters for research

- **Retrying a `null` answer reads nothing new.** You get the same job and the same `null`.
- **A page that changed since is not re-read.** An answer about today's price may be yesterday's.
- **A failed job stays failed** for the rest of the window — the same request returns it.

## What to do

Change the request when you want a new read: reword the question, start from a different page, or
change `discover`. Check `from_cache` on every submit.
