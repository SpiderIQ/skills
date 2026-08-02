# Reference: per-stage settings (the `workflow` block)

Both `/lead-search` and the campaign submit accept a `workflow` block that
configures each stage. Read this before composing any non-trivial run.

```json
"workflow": {
  "spidersite":   { "enabled": true, "mode": "leads" },
  "spiderverify": { "enabled": true, "max_emails_per_business": 10 },
  "vayapin":      { "enabled": false },
  "filter_social_media": true, "filter_review_sites": true,
  "filter_directories": true, "filter_maps": true
}
```

## Stage dependencies (enforced — 422 if violated)

- **SpiderVerify requires SpiderSite** (no crawl → no emails to verify).
- **VayaPin requires SpiderSite** (no website data → nothing to publish).
- Maps always runs.

## `spidersite` — crawl each website

| Setting | Default | Range / values | What |
|---|---|---|---|
| `enabled` | `false`* | bool | run the site crawl |
| `mode` | none | `contacts` · `compendium` · `leads` · `full` | preset (see below) — overrides `max_pages` |
| `max_pages` | `25` | 1–100 | pages per site (mode wins if set) |
| `crawl_strategy` | `bestfirst` | `bestfirst` · `bfs` · `dfs` | crawl order |
| `extract_team` | `false` | bool | AI team-member extraction |
| `extract_company_info` | `false` | bool | AI company profile |
| `extract_pain_points` | `false` | bool | AI challenge analysis |
| `product_description` | none | str | CHAMP scoring — **both or neither** with `icp_description` |
| `icp_description` | none | str | CHAMP scoring — **both or neither** with `product_description` |

\* `/lead-search` overrides this to `enabled: true, mode: "contacts"` when you omit
`workflow`.

### Modes (pick one; it sets the page budget + AI features)

| Mode | Pages | Use for |
|---|---|---|
| `contacts` | 5 | quick emails/phones, no AI |
| `compendium` | 5 | a markdown context doc about the business |
| `leads` | 25 | team + company extraction — the recommended default |
| `full` | 50 | deep extract, all AI features (slowest) |

CHAMP lead scoring (`product_description` + `icp_description`) grades each business
against your offer — supply **both** strings or **neither** (a one-sided pair 422s).

## `spiderverify` — verify the emails

| Setting | Default | Range | What |
|---|---|---|---|
| `enabled` | `false` | bool | SMTP-verify extracted emails |
| `check_gravatar` | `false` | bool | flag emails with a Gravatar |
| `check_dnsbl` | `false` | bool | check domains against spam blacklists |
| `max_emails_per_business` | `10` | 1–50 | caps verification cost; prioritises `contact@`, `info@`, … |
| `smtp_timeout_secs` | `45` | 10–120 | per-email SMTP timeout |

## `vayapin` — publish a map profile

| Setting | Default | What |
|---|---|---|
| `enabled` | path-dependent | publish a **real, permanent** pin on `cs.vayapin.com` per business with a website |

See the HARD-GATE and [vayapin-export.md](vayapin-export.md) — `enabled` defaults
**on** for `/lead-search` (omitted `workflow`) and follows your value on campaigns.
**Always set it explicitly.**

## Domain filters (on `workflow`, all default `true`)

`filter_social_media`, `filter_review_sites`, `filter_directories`, `filter_maps`
— drop Facebook/Yelp/YellowPages/Google-Maps URLs before the site crawl so you
crawl the real business site, not a directory listing. Leave them on unless you
specifically want those domains crawled.

## Cost intuition

`mode: full` (50 pages) + `extract_*` + a high `max_emails_per_business`, multiplied
across a campaign's locations × `max_results`, is the expensive corner. For broad
campaigns prefer `mode: contacts` or `leads`; reserve `full` for short lists.
