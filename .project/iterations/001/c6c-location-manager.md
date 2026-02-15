# zaap-c6c — Location Manager

## Delivered

Created `Zaap/Zaap/LocationManager.swift` — a `CLLocationManager` wrapper using `@Observable` (iOS 17+) with significant location change monitoring.

### API

- **`currentLocation: CLLocation?`** — latest location, observable via SwiftUI
- **`authorizationStatus: CLAuthorizationStatus`** — current auth status, observable
- **`isMonitoring: Bool`** — whether monitoring is active
- **`lastError: Error?`** — last error encountered
- **`locationPublisher: PassthroughSubject<CLLocation, Never>`** — Combine publisher for every location update
- **`requestAuthorization()`** — requests always authorization
- **`startMonitoring()`** — starts significant location change monitoring (auto-requests auth if needed)
- **`stopMonitoring()`** — stops monitoring

### Design Decisions

- Used `@Observable` macro (iOS 17+ Observation framework) instead of `ObservableObject`/`@Published` for modern SwiftUI integration
- Exposes both `@Observable` properties (for SwiftUI views) and a Combine `PassthroughSubject` (for services like the webhook client to subscribe)
- Requests "always" authorization since significant location changes require background capability
- Info.plist already has `NSLocationAlwaysAndWhenInUseUsageDescription` and `UIBackgroundModes: location` from the scaffolding bead

### Files Changed

- `Zaap/Zaap/LocationManager.swift` — new
- `Zaap/Zaap.xcodeproj/project.pbxproj` — added LocationManager.swift to build
