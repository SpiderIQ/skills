# Reference: the exact shape of a finished linkedinProfiles record

What a finished people job returns, per mode, field-by-field — so you read it
correctly and never tell the user a field is "missing" when it's just absent for
that mode/tier. This is the payload inside `/jobs/{job_id}/results`. The same people
are also reachable, sliced by type, through IDAP (see [read-results.md](read-results.md)).

## Always read `status` first

Every result carries a top-level **`status`**:

| `status` | Meaning |
|---|---|
| `success` | the scrape produced data (which may still be an empty list — see below) |
| `unavailable` | profile mode only — the profile is private/closed; payload is `{ mode, status: "unavailable", error, linkedin_url }`. **Terminal — do not retry.** |

A `failed` **job** (seen on `/status`, not in the payload) is a different thing —
usually a transient infra/provider blip, often fixed by one resubmit. See
[transient-vs-terminal-failures](../learnings/2026-05-26-transient-vs-terminal-failures/).

`source` tells you which engine answered: `brightdata` (profile), `brightdata_google`
(search), `apify` (company).

## profile mode (`source: brightdata`)

The worker returns these fields (flat on the result; the API may also expose them
nested under a `profile` object — read both):

| Field | Notes |
|---|---|
| `status` | `success` / `unavailable` |
| `linkedin_url` / `linkedin_id` / `linkedin_num_id` | URL, handle, numeric id |
| `first_name` / `last_name` / `full_name` | name |
| `headline` | professional headline (Bright Data `position`) |
| `about` | summary section |
| `location` / `city` / `country_code` | location string + parsed city + ISO country |
| `current_company` / `current_company_id` | current employer name + LinkedIn company id |
| `profile_pic_url` / `banner_image` / `default_avatar` | avatar URL, banner, and whether the avatar is LinkedIn's default placeholder |
| `connections` / `followers` | counts (may be null) |
| `experience[]` | `{ company, title, duration, company_logo_url }` |
| `education[]` | `{ title, description, start_year, end_year }` |
| `languages[]` | `{ name, proficiency }` |
| `memorialized_account` | `true` if the account is memorialized (deceased) |

## search mode (`source: brightdata_google`)

| Field | Notes |
|---|---|
| `status` | `success` |
| `query` | the query you sent |
| `google_query` | the actual `site:linkedin.com/in <query>` string that ran |
| `results_count` | `len(profiles)` |
| `profiles[]` | shallow results (below) |

Each `profiles[]` entry:

| Field | Notes |
|---|---|
| `linkedin_url` / `linkedin_id` | normalized profile URL + handle |
| `name` | parsed from the Google title — **best-effort**, may be imperfect or null |
| `headline` | parsed from the Google title (text after `" - "`); may be null |
| `location` | parsed from the snippet — **often null** |
| `snippet` | the raw Google snippet |

- Shallow by design. Re-run a `linkedin_url` through profile mode for the full record.

## company mode (`source: apify`)

| Field | Notes |
|---|---|
| `status` | `success` |
| `company_url` / `company_slug` | the URL you sent + the extracted slug |
| `profile_mode` | echoes the tier you ran (`short`/`full`/`full_email`) |
| `employees_count` | `len(employees)` |
| `employees[]` | employee records (below) |

Each `employees[]` entry — **always present** fields:

| Field | Notes |
|---|---|
| `full_name` / `first_name` / `last_name` | name |
| `title` | current title (from Apify `currentPositions[0].title`) |
| `location` | location string (flattened from Apify's `location.linkedinText`) |
| `linkedin_url` / `linkedin_id` | profile URL + id |
| `profile_pic_url` | picture URL |
| `premium` | `true` if a LinkedIn Premium account |
| `open_profile` | `true` = accepts InMail without a connection (outreach signal) |

**Tier-gated** employee fields:

| Field | Appears when | Shape |
|---|---|---|
| `experience` | `full` / `full_email` | **RAW Apify structure** — NOT the normalized `experience[]` profile mode returns |
| `education` | `full` / `full_email` | RAW Apify structure |
| `skills` | `full` / `full_email` | RAW Apify list |
| `email` | `full_email` **and** Apify found one | string; absent when none discovered |

> **Cross-mode shape warning:** `experience`/`education` in **company** mode are
> raw Apify objects passed through verbatim; in **profile** mode they're the
> normalized `{company,title,duration,...}` / `{title,description,start_year,...}`
> shapes. Do not assume the same keys across modes.

## Reading the same data via IDAP

| Mode output | IDAP read |
|---|---|
| profiles / employees | `GET /idap/linkedin_profiles` |
| people as contacts | `GET /idap/contacts` |

Populated by the CRM sync after the job completes (a short lag) — see
[read-results.md](read-results.md).

## Gotchas

- **Branch on `mode` before reading.** Only the active mode's container is populated
  (`profile` fields / `profiles[]` / `employees[]`); the others are empty/absent.
- **Counts and parsed fields can be null.** `connections`/`followers`, and search
  `name`/`headline`/`location`, are best-effort — absent means "not available", not
  "zero".
- **Image URLs may expire.** `profile_pic_url` / `banner_image` are provider CDN
  links; persist anything you need to keep.
- **Empty is valid.** `profiles: []`, `employees_count: 0`, or `status: unavailable`
  are legitimate completed results — see
  [empty-is-not-failure](../learnings/2026-05-26-empty-is-not-failure/).
