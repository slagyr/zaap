# zaap-2xf: HealthKit Sleep Data Reader

## What was done

### New file: `SleepDataReader.swift`
- `SleepDataReader` class with `@Observable` for SwiftUI integration
- `requestAuthorization()` — requests read-only access to `HKCategoryType.sleepAnalysis`
- `fetchSleepSamples(from:to:)` — queries HealthKit for sleep samples in a date range (defaults to last night: 6 PM yesterday → noon today)
- `fetchLastNightSummary()` — aggregates raw samples into a `SleepSummary` with:
  - Bedtime, wake time, date
  - Total in-bed, total asleep, deep, REM, core, awake minutes
  - Full list of `SleepSession` objects (each with stage, start/end, duration)
- All types (`SleepSummary`, `SleepSession`) are `Codable` + `Sendable`, ready for webhook POST
- Handles all Apple sleep stages: inBed, asleepCore, asleepDeep, asleepREM, asleepUnspecified, awake

### Updated: `SettingsManager.swift`
- Added `sleepTrackingEnabled` toggle (persisted to UserDefaults)

### Updated: `Info.plist`
- Added `NSHealthShareUsageDescription` for HealthKit read access

### New file: `Zaap.entitlements`
- Added `com.apple.developer.healthkit` entitlement

### Updated: `project.pbxproj`
- Added SleepDataReader.swift and Zaap.entitlements to project
- Added CODE_SIGN_ENTITLEMENTS to Debug and Release configs

## Notes
- Read-only access — no `toShare` types requested (we only read sleep data)
- Could not verify build (no full Xcode on this machine, only CommandLineTools)
- The downstream bead `zaap-ku4` will wire this into the webhook POST flow
