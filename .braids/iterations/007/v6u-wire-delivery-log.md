# zaap-v6u: Wire DeliveryLogService into delivery service singletons

## Summary

All five delivery services were previously hardcoded to use `NullDeliveryLog()` as
their delivery logger, meaning no delivery events were ever persisted to SwiftData.
The Dashboard had no records to display.

## Changes

### Delivery Services (×5)

Added `configure(deliveryLog: any DeliveryLogging)` and changed `private let deliveryLog`
to `private var deliveryLog` in each service:

- `LocationDeliveryService.swift`
- `SleepDeliveryService.swift`
- `HeartRateDeliveryService.swift`
- `ActivityDeliveryService.swift`
- `WorkoutDeliveryService.swift`

### ZaapApp.swift — `startServices()`

- Creates `DeliveryLogService(context: modelContainer.mainContext)` at app launch
- Calls `.configure(deliveryLog:)` on all five singletons before `.start()`
- Also wires in `HeartRateDeliveryService` and `WorkoutDeliveryService` which were
  previously not started at all

## Verification

`xcodebuild build` → **BUILD SUCCEEDED** (iPhone 17 Pro simulator)

## Impact

Dashboard delivery records will now appear. Every successful/failed delivery event
across location, sleep, heart rate, activity, and workout services is persisted to
SwiftData via `DeliveryLogService`.
