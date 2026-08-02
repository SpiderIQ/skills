---
name: manage-browser-profiles
version: 1.0.0
description: Create and manage anti-detect browser profiles using Camoufox — for authenticated scraping, cookie export, email warmup, and platform session management.
client: manage-browser-profiles
client_version: "1.0.0"
category: automation
triggers:
  - browser profile
  - create browser
  - export cookies
  - warmup account
  - manage browser
  - anti-detect browser
  - start browser
  - browser screenshot
requires_auth: false
requires_brand: false
metadata:
  openclaw:
    emoji: "\U0001F310"
    primaryEnv: OPVS_PAT
---

# Manage Browser Profiles — Anti-Detect Automation

**PREREQUISITE:** Read `../opvs-foundation/SKILL.md` first.

## Purpose

Create and manage anti-detect browser profiles using Camoufox for C++-level fingerprint spoofing. Enables persistent authenticated sessions on platforms like YouTube, LinkedIn, Instagram, SmartLead, and Google Maps. Used for cookie export, email warmup, and maintaining realistic browsing profiles.

## When to Use

- User needs to create browser profiles for platform access
- User wants to export authenticated cookies (e.g., YouTube for yt-dlp)
- User needs to warm up email accounts across 200+ SmartLead accounts
- User wants to manage LinkedIn/Instagram sessions with realistic fingerprints
- User needs to start/stop browsers or take screenshots

## Profile Lifecycle

```
new -> warming_up -> active (production ready)
                  -> needs_login (session expired)
                  -> banned / cooldown (rate limited)
```

## Decision Guidance

### Choosing a Platform

Each profile targets a specific platform. Supported platforms: `youtube`, `linkedin`, `instagram`, `smartlead`, `google_maps`. The platform determines which fingerprint characteristics and warmup behavior patterns are used.

### Warmup Protocol

New profiles need a 2-3 week warmup progression before production use:

1. **Week 1:** 15-30 min/day -- light browsing, random searches
2. **Week 2:** 30-60 min/day -- normal activity, video watching
3. **Week 3:** Full production deployment

Skipping warmup dramatically increases ban risk. Always start warmup before using profiles for automation.

### Headless vs Headed Mode

- **Headless** (`headless: true`): Use for automated tasks, cookie export, screenshots. No VNC access.
- **Headed** (`headless: false`): Use for manual login, debugging, visual verification. Returns VNC URL at `http://localhost:6080/vnc.html`.

## Anti-Patterns

- Do not run more than 10 concurrent browsers per worker -- 512MB memory per instance
- Do not skip warmup for new profiles -- leads to immediate bans
- Do not start multiple profiles for the same platform and account simultaneously
- Do not store plaintext passwords in notes -- use the encrypted `password` field
- Do not use profiles in `banned` or `cooldown` status -- wait for cooldown to expire

## Response Guidelines

- Show profile status clearly (new/warming_up/active/needs_login/banned)
- After starting a browser, show VNC URL if headless=false
- For cookie exports, confirm format (JSON + Netscape) and expiry date
- Report pool status (active count, memory usage) when managing multiple profiles
- Warn if approaching the 10-browser concurrent limit

## Available Methods

| Method | Description |
|--------|-------------|
| `createProfile` | Create a new browser profile with anti-detect fingerprinting |
| `listProfiles` | List all browser profiles, optionally filtered by platform or status |
| `startBrowser` | Launch a browser session using a profile |
| `stopBrowser` | Stop a running browser session |
| `exportCookies` | Export all cookies from a browser profile's session |
| `getPoolStatus` | Get browser pool status including active sessions and resources |
