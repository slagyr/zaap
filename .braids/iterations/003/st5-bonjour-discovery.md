# zaap-st5: Bonjour Discovery

## Summary
Implemented Bonjour/mDNS discovery for OpenClaw gateways on the local network using NWBrowser.

## Files Added
- `Zaap/Zaap/GatewayBrowser.swift` — Model (`DiscoveredGateway`), protocol (`GatewayBrowsing`), real NWBrowser wrapper (`NWGatewayBrowser`), and ViewModel (`GatewayBrowserViewModel`)
- `Zaap/ZaapTests/GatewayBrowserTests.swift` — 13 tests covering model, viewmodel, and settings integration

## Files Modified
- `Zaap/Zaap/SettingsView.swift` — Added discovered gateways picker section above manual hostname entry
- `Zaap/Zaap/MainTabView.swift` — Wired `GatewayBrowserViewModel` into SettingsView
- `Zaap/Zaap.xcodeproj/project.pbxproj` — Added new files to build targets

## Design
- `GatewayBrowsing` protocol enables full testability without real network
- `NWGatewayBrowser` wraps `NWBrowser` for `_openclaw._tcp` service type
- SettingsView shows a "Discovered Gateways" section with checkmark for selected, falls back to manual entry when none found
- Selected gateway hostname stored in existing `webhookURL` UserDefaults key
- Port 443 is treated as default and omitted from the hostname string

## Tests
All 13 tests pass. Pre-existing VoiceChatViewModelTests failures are unrelated (MainActor isolation issues).
