# `scheduled` does not mean "will publish itself"

## What happened

The press agent surface (MCP tools + CLI + this skill) was built against the
live dashboard press API. `POST /press/{id}/schedule` is a real, working
endpoint: it validates that the timestamp is in the future, rejects a past one
with a 400, and moves the release to `status='scheduled'` with `published_at`
set. A round-trip through MCP confirmed all of that.

What it does **not** do is publish the release when that moment arrives. There
is no sweeper. The status sits at `scheduled` indefinitely until something calls
`publish`.

## Why it is easy to get wrong

Every signal points the other way:

- the endpoint exists and returns 200
- the status vocabulary includes `scheduled`
- `published_at` is populated with the future time
- a past timestamp is correctly rejected

Nothing in the response hints that the second half of the feature is missing.
An agent — or a person reading the API — reasonably concludes the release is
queued to go out. It is not.

## What to do

- Call `publishPressRelease` at the moment you want a release live.
- Use `schedulePressRelease` to record intent and to keep the newsroom's own
  status legible, not as a delivery mechanism.
- Never promise a client an unattended timed launch on this surface today.
- Re-check before relying on it: when the sweeper slice ships, this learning
  goes stale and scheduling becomes real.

## The same shape, one step further: embargo

`embargo_until` and `embargo_token` exist as columns, and `embargoed` is a valid
status — but there is **no embargo endpoint at all**, and nothing mints a token.
The agent surface deliberately ships no `embargo` method rather than wrapping a
route that does not exist. Treat any embargo affordance you think you see as
not-yet-built until an endpoint answers.

## The general rule

A status value in an enum is evidence that someone *planned* a behavior, not
that the behavior runs. Before building on a lifecycle state, find the thing
that *transitions out of it*. If no code moves a row out of a state, that state
is a label, not a promise.
