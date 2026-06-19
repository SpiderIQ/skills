## manage-locations

The global location database backing campaigns and lead research. 9 tools — add cities and postcodes, view coverage stats, find gaps, expand campaign reach.

### What this skill does

- **Country coverage stats** — `get_country_coverage` returns city count, postcode count, last update timestamp per country. Tells you whether SpiderIQ has enough density to launch a campaign in a given country.
- **Cities** — `list_cities`, `add_city`, `update_city`. City is the granularity for SpiderMaps search — a campaign targeting "plumbers in Bavaria" iterates over cities.
- **Postcodes** — `list_postcodes`, `add_postcode`. Postcode-level granularity for tighter targeting within dense urban areas.
- **Gap analysis** — `find_coverage_gaps` returns regions where postcode density is below the threshold. Used before campaign launch to surface "we don't have enough coverage in region X — expand or skip".
- **Bulk import** — `import_locations` accepts a CSV/JSON of cities or postcodes. Used by ops when SpiderIQ adds a new country.

### Typical workflows

- **Pre-launch coverage check** — agent calls `get_country_coverage` for the campaign's target country, decides whether to launch, expand, or pivot.
- **Expansion** — agent identifies a coverage gap, runs a CSV import to fill it.
- **Audit** — agent queries postcode density per region for a quarterly coverage report.

### Why this is admin-skills, not lead-gen-skills

Reading the location DB is implicit in every lead-gen call. **Writing** it is admin-level — adding a postcode that doesn't actually exist or removing real ones breaks campaigns silently across every brand. Reserved for trusted agents.
