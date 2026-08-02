---
name: extract-website-branding
version: 1.0.0
description: Extract brand design (colors, fonts, logo) from any website URL using Firecrawl, then apply it to AgentDocs public documentation themes.
client: extract-website-branding
client_version: "1.0.0"
category: design
triggers:
  - brand design
  - extract branding
  - match website design
  - design like
  - look like
  - brand colors
requires_auth: false
requires_brand: false
metadata:
  openclaw:
    emoji: "\U0001F3A8"
---

# Firecrawl Brand Extraction

Extract a complete brand design from any website URL and apply it to AgentDocs public documentation themes. This lets clients say "make my docs look like my website" and you handle the rest.

## Decision Guidance

### Two-Step Workflow

1. **Extract first, then apply** -- always scrape the website branding before making any theme changes. Never guess colors or fonts.
2. **Map extracted values to theme fields** -- use the mapping below to translate Firecrawl output to `docs_update_theme` input.

### Firecrawl-to-Theme Mapping

| Firecrawl field | docs_update_theme field |
|----------------|------------------------|
| `colors.primary` | `theme.colors.primary` |
| `colors.accent` | `theme.colors.accent` |
| `colors.background` | `theme.colors.background` |
| `colors.secondary` | `theme.colors.surface` |
| `colors.textPrimary` | `theme.colors.text` |
| `colors.textSecondary` | `theme.colors.textMuted` |
| Derive from background | `theme.colors.border` (see below) |
| `typography.fontFamilies.heading` | `theme.fonts.heading` |
| `typography.fontFamilies.primary` | `theme.fonts.body` |
| `typography.fontFamilies.code` | `theme.fonts.code` (fallback: "JetBrains Mono") |
| `images.logo` | `theme.logo.url` |
| `images.favicon` | `theme.favicon.url` |

### Border Color Derivation

- If `colorScheme` is "dark": lighten the background by ~15% for the border
- If `colorScheme` is "light": darken the background by ~10% for the border

### Fallback Defaults

- If no code font is returned, use "JetBrains Mono"
- If no favicon is found, omit the field (theme keeps current value)
- The theme deep-merges, so you only need to send changed fields

## Anti-Patterns

- Do not guess brand colors -- always extract from the actual website first
- Do not apply a theme without telling the client what was extracted and what will change
- Do not hardcode font stacks -- use the exact font family names from the extraction

## Response Guidelines

- Show the client what you extracted: colors, fonts, logo URL
- Explain what you will apply and let them request adjustments
- After applying, confirm the theme update was successful

## Available Methods

| Method | Description |
|--------|-------------|
| `extractBranding` | Scrape a website URL and extract colors, typography, logos, and design patterns |
