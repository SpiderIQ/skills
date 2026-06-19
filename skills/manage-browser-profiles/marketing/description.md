## manage-browser-profiles

Direct access to SpiderIQ's anti-detect browser pool. 6 tools — create profiles, start/stop sessions, export cookies, monitor pool health.

### What this skill does

- **Profiles** — `list_profiles`, `create_profile`, `delete_profile`. A profile is a persistent browser identity (cookies, local storage, fingerprint config). Used for long-running scrape workflows that need a stable identity across runs.
- **Sessions** — `start_session`, `stop_session`. A session is an active browser instance bound to a profile. Most workflows let SpiderBrowser auto-allocate; direct control is for cases where an agent needs to keep a session warm across multiple operations.
- **Cookies** — `export_cookies` returns a profile's cookies in standard format for handing off to other tools or for audit.

### Architecture

SpiderIQ runs ~11 SpiderBrowser instances across the VPS fleet, with 48 profiles total. Camoufox-backed (anti-detect Firefox fork) — fingerprint randomization, WebRTC leak prevention, canvas noise injection. Most lead-gen skills (SpiderMaps, SpiderSite) use the pool transparently via internal allocation.

### When agents need direct control

- **Long-running campaigns** — agent provisions a dedicated profile for a multi-day scrape so cookies persist across runs.
- **Account-bound scraping** — profile holds a logged-in session for sites that gate content behind auth.
- **Capacity management** — admin agent monitors pool depth, pre-warms profiles before a scheduled campaign launch.

### When NOT to call

For one-off scrape jobs, use the data-collection skills (SpiderMaps, SpiderSite) and let them allocate from the pool. Direct profile management is overhead the workflow doesn't need.
