# HealthKit Observer Queries — Background Delivery

## Summary

Replaced the one-shot-on-launch delivery pattern with HKObserverQuery + enableBackgroundDelivery for all HealthKit types. When the Apple Watch or any app writes new data, iOS wakes Zaap and it fetches+delivers immediately.

## Files Added/Modified

### New Files
- `Zaap/Zaap/HealthKitObserverService.swift` — Core service managing observer queries and background delivery registration
- `Zaap/Zaap/ObserverDeliveryAdapter.swift` — Bridges observer callbacks to existing delivery services
- `Zaap/ZaapTests/HealthKitObserverServiceTests.swift` — 8 tests covering all service behavior

### Modified Files
- `Zaap/Zaap/ZaapApp.swift` — Wires HealthKitObserverService into app startup
- `Zaap/Zaap/Info.plist` — Added `fetch` to UIBackgroundModes
- `Zaap/Zaap.xcodeproj/project.pbxproj` — Added all new files to build targets

## Architecture

- **ObservedHealthDataType** enum: `.heartRate`, `.sleep`, `.activity`, `.workout`
- **ObserverFrequency** enum: `.immediate`, `.hourly` — maps to HKUpdateFrequency
- **HealthKitObserverBackend** protocol: Abstracts HKHealthStore for testability
- **HKObserverBackend**: Production implementation wrapping HKHealthStore
- **ObserverDeliveryDelegate** protocol: Called when observer fires to perform data fetch+delivery
- **ObserverDeliveryAdapter**: Production delegate that routes to existing delivery services

## Background Delivery Frequencies
- Heart rate: `.immediate` — fires as watch records samples
- Workouts: `.immediate` — fires when workout session ends
- Sleep: `.immediate` — fires when sleep session is written
- Activity/Steps: `.hourly` — steps update constantly, hourly batching is fine

## Tests (8 passing)
- Start does nothing when not configured
- Start registers observers for all enabled types
- Start only registers enabled types
- Start uses correct frequencies per type
- Observer callback triggers delivery delegate
- Observer callback calls completion handler (critical for iOS throttling)
- Stop removes all observers
- Start is idempotent (stops old observers first)
