# zaap-0a2: Background Location Delivery

## Summary

Wired LocationManager → WebhookClient so location updates are POSTed to the configured webhook endpoint, including when the app is backgrounded.

## Changes

### New: `LocationDeliveryService.swift`
- Subscribes to `LocationManager.locationPublisher` via Combine
- On each location update, encodes a `LocationPayload` and POSTs via `WebhookClient`
- Guards on `settings.isConfigured` and `settings.locationTrackingEnabled` before sending
- Resumes monitoring on app launch if tracking was previously enabled
- `setTracking(enabled:)` method for UI toggling

### Modified: `ZaapApp.swift`
- Initializes `LocationDeliveryService.shared.start()` at app launch
- Passes `LocationManager` into the environment

### Modified: `SettingsView.swift`
- Added `.onChange` on the location tracking toggle to call `LocationDeliveryService.shared.setTracking(enabled:)`

### Modified: `WebhookClient.swift`
- Fixed `loadConfiguration()` to read from `SettingsManager.shared` instead of raw UserDefaults keys (was using different keys than SettingsManager)

## Background Delivery

- `UIBackgroundModes: location` already in Info.plist
- `CLLocationManager.startMonitoringSignificantLocationChanges()` delivers in background
- `WebhookClient` uses `URLSessionConfiguration.background` with `isDiscretionary = false` and `sessionSendsLaunchEvents = true`
- Combine subscription persists as long as the service lives (singleton)

## Payload Format

```json
{
  "latitude": 33.4484,
  "longitude": -112.0740,
  "altitude": 331.0,
  "horizontalAccuracy": 65.0,
  "verticalAccuracy": 10.0,
  "speed": -1.0,
  "course": -1.0,
  "timestamp": "2026-02-15T19:03:00Z"
}
```
