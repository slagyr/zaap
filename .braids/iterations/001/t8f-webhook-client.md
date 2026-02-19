# zaap-t8f: Webhook Client

## Deliverable

Added `Zaap/Zaap/WebhookClient.swift` — a self-contained webhook client.

### Features
- **Background URLSession** (`com.zaap.webhook`) — uploads complete even when app is suspended
- **Bearer token auth** — `Authorization: Bearer <token>` header on every request
- **Configurable** — reads `webhookURL` and `webhookToken` from UserDefaults (ready for Settings screen zaap-x6c)
- **Generic payload** — `post<T: Encodable>(_ payload:, to path:)` accepts any Encodable with optional path appending
- **ISO 8601 dates** — encoder configured for standard date format
- **File-based upload** — writes payload to temp file (required for background URLSession upload tasks)
- **Structured logging** — uses `os.Logger` for all events
- **Error handling** — typed `WebhookError` enum: noConfiguration, invalidResponse, encodingFailed, networkError
- **Session delegate** — handles `urlSessionDidFinishEvents` (completion handler wiring deferred to zaap-0a2)

### Usage
```swift
let location = LocationPayload(latitude: 33.45, longitude: -111.94, timestamp: .now)
try await WebhookClient.shared.post(location)
```

### Notes
- Could not compile-verify — no Xcode/iOS SDK on build host. Code uses standard Foundation + os APIs only.
- Background session completion handler hookup left for zaap-0a2 (background delivery bead).
