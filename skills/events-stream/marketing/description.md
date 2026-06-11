## events-stream

Server-Sent Events stream of live agent activity. One tool, one open connection, real-time visibility into what the brand's agents are doing.

### What this skill does

- **`subscribe_events`** — opens an SSE connection to `/api/v1/events/stream`. Streams JSON-formatted events as they happen: job submissions, status transitions (`processing` → `completed`/`failed`), worker heartbeats, error reports.

### Typical workflows

- **Real-time monitoring dashboards** — an agent subscribes, parses events, updates a status panel for human operators.
- **Reactive workflows** — an agent waits for a specific job's `completed` event before kicking off a downstream task, instead of polling `/jobs/<id>/status`.
- **Audit / observability** — long-running agent that logs every event for the brand, building a real-time activity feed.

### Filtering

Events are scoped to the active brand server-side. Optional client-side filters via query params: `?type=job.completed&service=spiderSite` narrows the stream to specific event types.

### Reliability

SSE handles reconnection automatically (browsers + most SDKs). Server keeps a 30-second heartbeat to detect dead connections. Last-Event-ID is honored — clients reconnecting after a disconnect resume from where they left off (5-minute backlog buffer).
