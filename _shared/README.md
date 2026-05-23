# _shared

Cross-product references that multiple SpiderIQ skills cite. When two or more
skills need the same procedural knowledge, the canonical version lives here
and the per-skill recipes link to it via relative path
(`../_shared/<file>.md`).

## Current files

(none yet — files land here when the first cross-product reference is needed)

## Likely first inhabitants

- `auth.md` — the PAT auth pattern used by every SpiderIQ product (request
  access, bind project via `spideriq use`, refresh, scope rules, the
  five-lock client-isolation contract that catalog/SpiderMail/SpiderGate all
  enforce identically)
- `errors.md` — the structured error-envelope shape returned by every
  SpiderIQ API (`{code, message, what_you_sent, what_was_expected,
  suggested_action, suggested_url, docs}`) — what to read first when a tool
  call returns 4xx/5xx
- `format-llm.md` — the `?format=llm` opt-in + the OPVS `guidance` block
  (frozen 6-key vocab: `use / not / next / warn / pitfalls / limits`)
