# A failed vault create echoed the pasted key back into the agent's chat

## What happened

Two faults met. The 422 handler returned the whole request body in
`what_you_sent`; only the log line was redacted. And the one MCP tool that
added a vault key, `create_brand_integration`, sent `{provider, api_key, label}`
while the route takes `{provider_name, credentials, key_label}`. So every call
was a 422, and every 422 handed the key back to the agent — which the design
forbids — while nothing was saved.

## What changed

- The vault create refuses an unknown field by NAME, before field validation,
  so its answer never carries the value.
- A key that fails the provider's check is a 422 that names the reason, with
  the key redacted. Nothing is stored.
- `create_brand_integration`, the workspace skill and this skill send the
  route's own field names.
- The agent surface (`gate_add_key`, `spideriq gate setup add-key`) scrubs every
  secret it was given out of any error text before returning it.

## What to do

- Build the body from the route's own fields: `provider_name`,
  `credentials: {api_key, …}`, `key_label`.
- Answer by reference ("saved your Groq key"), never by value — on success and
  on failure.
- If an error you are about to repeat contains anything key-shaped, do not
  repeat it. Say the reason in your own words.
