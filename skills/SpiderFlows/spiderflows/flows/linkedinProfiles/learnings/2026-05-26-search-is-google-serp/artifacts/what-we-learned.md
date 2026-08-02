# search mode is a Google first-page lookup — shallow, capped, and not LinkedIn login

**Starting point, not ground truth — verify against current code.**

## The surprise

"Search LinkedIn for VP Sales in Berlin" sounds like it queries LinkedIn. It
doesn't. `linkedinProfiles` **search** mode runs a **Bright Data Google SERP**: it
Googles `site:linkedin.com/in <your query>`, takes the organic results from the
**first page only**, and keeps the `/in/` URLs. No LinkedIn login, no proxy — and
that design sets three hard constraints.

## The three constraints (all matter for real results)

1. **First page only.** The worker requests `start=0` and never paginates. After
   filtering to profile URLs, you typically get **fewer than 10** hits — sometimes
   zero on a niche query. That's a normal SERP outcome (`results_count: 0`,
   `status: success`), not a failure.
2. **`search_limit` is capped at 25 in the worker.** The API/Pydantic accepts up to
   50, but the worker clamps to `min(n, 25)` — and the first-page ceiling usually
   bites first. **Never promise the user 50 profiles from one search.**
3. **Results are shallow.** Each hit is `linkedin_url`, `name`, `headline`,
   `location`, `snippet` — parsed from the Google result, not a profile. `name` and
   `headline` are split out of the Google title (can be imperfect or null);
   `location` is best-effort from the snippet (often null).

## The right way to use it

- Use search to **discover candidate profile URLs** from a description, then enrich
  the ones that matter by running each `linkedin_url` through **profile** mode
  (a separate ~$0.003 job each). Search → identify; profile → enrich.
- Don't add `site:linkedin.com/in` yourself — the worker prepends it. Write a natural
  query: title + domain + place.
- If the user wants *many* people from one company, that's **company** mode (the
  employee roster), not search.

## The scope boundary (don't confuse the two services)

There is a **separate**, authenticated LinkedIn search — SpiderPublicLinkedin
(`linkedinSearch.yaml`, Voyager `search_people`) — that requires managed LinkedIn
accounts + mobile proxies and is warmup-rate-limited. It is a **different flow** and
is **not** part of `linkedinProfiles`. If a user explicitly needs authenticated
Voyager-grade people search, that's the other service.

## Rule of thumb

- Search = a thin Google reflection of LinkedIn: a handful of shallow hits, fast and
  cheap (~$0.01). Set that expectation, then enrich the keepers.
