# zaap-x6c: Settings Screen

## Deliverables

### SettingsManager.swift
- `@Observable` singleton managing three settings: `webhookURL`, `authToken`, `locationTrackingEnabled`
- Persisted via UserDefaults with immediate `didSet` writes
- Convenience computed properties: `webhookURLValue` (validated URL), `isConfigured` (URL + token present)
- Accepts injected `UserDefaults` for testability/previews

### SettingsView.swift
- SwiftUI Form with three sections: Webhook config, Data Sources toggle, Summary
- Webhook URL field with URL keyboard type
- Auth token as SecureField with eye toggle for visibility
- Location tracking toggle with warning when enabled but not configured
- Summary section shows endpoint and active/inactive status
- iOS 17+ using `@Bindable` with `@Observable`

### ContentView.swift (updated)
- Now hosts `SettingsView` inside a `NavigationStack`
- Owns `SettingsManager.shared` instance

## Design Decisions
- **UserDefaults over Keychain** for the auth token: simpler, sufficient for a personal-use app with a single webhook. The token is for a local tailnet endpoint. Can migrate to Keychain later if needed.
- **No third-party deps** per guardrails
- **`@Observable` macro** consistent with existing `LocationManager` pattern
