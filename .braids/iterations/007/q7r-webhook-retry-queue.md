# zaap-q7r — Webhook Retry Queue

## Problem

When connectivity drops (e.g. in-flight, tunnel, dead zone), webhook POSTs to `/hooks/*`
fail and are silently dropped. The data is lost permanently even though the original event
(with its timestamp) is still valid and useful.

Confirmed by real-world usage: location POSTs during a Sedona flight returned errors and
were never retried.

## Goal

Failed webhook POSTs are queued to disk and retried when connectivity is restored,
preserving the original payload timestamp.

## Design

### Retry Queue (persistent)
- File: `Application Support/retry_queue.json`
- Each entry: `{ id, url, payload, headers, failedAt, attemptCount, nextRetryAt }`
- Payload is stored as-is (original timestamp preserved — the gateway receives it with
  the correct event time, not the retry time)
- Max queue size: 500 entries
- Max age: 24 hours (older entries are pruned on drain)
- Max attempts: 5 (drop after 5 failures)

### Integration Point
`WebhookClient` (or a new `WebhookRetryQueue` service it delegates to) intercepts failed
requests and enqueues them instead of throwing. On success, remove from queue.

### Retry Trigger
`NWPathMonitor` already exists in the codebase (`NWNetworkMonitor`). When path transitions
from `.unsatisfied` → `.satisfied`, drain the queue oldest-first.

### Backoff
Exponential backoff: 30s → 2m → 8m → 30m → 2h. Stored as `nextRetryAt` in each entry.
On app resume, also attempt to drain (in case connectivity was restored while backgrounded).

### UI
Request log (existing) should mark retried entries differently — e.g. show original
timestamp but note "retried". Or just show the original timestamp as normal (transparent retry).

## Constraints
- TDD: tests before implementation
- No third-party deps
- All new Swift files added to project.pbxproj
- Build verify only — do NOT run `xcodebuild test`
- Do NOT push to TestFlight

## Priority
P1 — data loss confirmed in production
