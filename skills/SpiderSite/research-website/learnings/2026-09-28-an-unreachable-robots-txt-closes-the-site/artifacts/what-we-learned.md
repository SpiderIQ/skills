# An unreachable robots.txt closes the whole site

Research reads robots.txt before anything else and follows RFC 9309:

| robots.txt | Means |
|---|---|
| answers 2xx | its rules apply to every page (the `SpiderIQ` group, or `*`) |
| answers 4xx — usually 404, no file | no rules: the whole host may be read |
| answers 5xx, times out, or cannot be reached | the WHOLE host is disallowed |

The last row surprises people: a site whose robots.txt is down is closed, not open. The standard
says so because a server that cannot serve its rules cannot be assumed to allow anything.

## The measured case

`https://www.google.com/search?q=spideriq` with `discover: "single"`: google.com's robots.txt
disallows `/search`. Nothing was fetched, and the job failed in 0.6 s. The message, as it reads
today (the PDF count was added after this run):

```
[research_no_readable_pages] No page could be read, so there is no answer; 1 disallowed by
robots.txt, 0 refused as unsafe, 0 failed to load, 0 PDF not read because PDF reading was not
requested.
```

## What to do with it

- It is the site's answer, not an outage: the job is not retried, and resubmitting fails the same
  way.
- Look at `skipped[]` on a completed job, or the counts in the failure: `robots_disallowed` is a
  rule; `robots_unreachable` is a robots.txt that could not be read.
- Start on a page the rules allow — or, only for a site the user owns or has permission to read,
  set `respect_robots: false`.
