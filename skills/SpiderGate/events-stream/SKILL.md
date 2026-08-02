---
name: events-stream
version: "1.0.0"
description: >
  Real-time job event monitoring via Server-Sent Events. Subscribe to job lifecycle events (queued, started, completed, failed) and check event stream health.

category: monitoring
requires_auth: true
requires_brand: false
triggers:
  - job events
  - live stream
  - event status
  - real-time monitoring
client: events-stream
client_version: "1.0.0"
metadata:
  openclaw:
    primaryEnv: SPIDERIQ_PAT
---

# Events Stream

## When to Use

<!-- TODO: Add decision guidance — when should the agent reach for this skill? -->

## Key Rules

<!-- TODO: Add business rules, constraints, lifecycle rules -->

## Anti-Patterns

<!-- TODO: Add things the agent should NOT do -->

## Available Methods

All methods are available via `events-stream_*` tool calls:

- `events-stream_getEventStatus()` — Get event stream status — service health, active subscriptions, and whether your client is currently connected.
