Distribute a press release the client has written over the newswire. Submit the
release (title + body, plus optional summary, category, keyword tags, and a press
contact); SpiderIQ renders it to wire-ready HTML and submits it to the
distribution provider asynchronously. The submit returns a `job_id` — poll
`getJobStatus`, then read `getJobResults` for the live `published_url` and the
provider's wire report once the release goes live. Optional `scheduled_release_at`
for embargoed announcements, and a `test` flag to exercise the path without a
live distribution.

Each submit is a paid, irreversible distribution, so the skill treats submit and
publish as two distinct events: it never reports a link off the submit response
(there isn't one yet) and never blind-retries a submit (that sends a second
release). Use `@spideriq/publish-skills` instead to host a newsroom page on the
client's own site, or `@spideriq/mail-skills` for email outreach.
