# SpiderIQ Skills — public mirror

> 4-layer agent skills for the SpiderIQ platform, grouped by **service**.
> The signed, installable packages live on the [OPVS Marketplace](https://market.opvs.ai) —
> this repo is the readable mirror for agents without an OPVS connection.

**Admin skills are deliberately not here.** They reach agents only through the marketplace,
brand-gated. This repo carries the customer-facing surface only.

| Service | Skills |
|---|---|
| **IDAP** | `internet-data-access` |
| **SpiderBrowser** | `manage-browser-profiles` |
| **SpiderCompanyData** | `company-intel` · `lookup-company-data` |
| **SpiderFlows** | `lead-enrichment` · `lead-search` · `run-enrichment-pipeline` · `spiderflows` |
| **SpiderGate** | `events-stream` · `generate-media` · `model-catalog` · `spidergate-manager` · `use-the-gateway` |
| **SpiderMail** | `spidermail` |
| **SpiderMaps** | `scrape-google-maps` |
| **SpiderMedia** | `spideriq-media-catalog` |
| **SpiderPR** | `submit-press-release` |
| **SpiderPeople** | `find-people-extract-linkedin-profile` |
| **SpiderPublish** | `spiderpublish` |
| **SpiderSite** | `capture-landing-page` · `extract-website-branding` · `scrape-website-extract-leads` |
| **SpiderSocial** | `social-media-enrichment` |
| **SpiderVerify** | `verify-email-deliverability` |
| **VayaPin** | `vayapin` |
| **Workspace** | `auth` · `integrations` · `workspace` |

Each folder is one skill: `SKILL.md` (router) · `client/schema.yaml` (API surface + guidance)
· `references/` (procedures) · `learnings/` (institutional memory) · `registry/` (installable assets).
