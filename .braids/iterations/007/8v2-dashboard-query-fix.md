# zaap-8v2 — Dashboard @Query Showing No Data After Send Now

## Root Cause

`DeliveryLogService.record()` called `context.insert(record)` but never called `context.save()`.

SwiftData's `@Query` observes the **persistent store** (SQLite) via change notifications emitted when a `ModelContext` is saved. Without `save()`, newly inserted `DeliveryRecord` objects exist only in the context's in-memory pending state — they are never written to the store, so `@Query` never receives a change notification and its result set never updates.

### Why `@Query` doesn't see unsaved inserts

- `DashboardView` gets its `ModelContext` from the SwiftUI environment (injected by `.modelContainer(modelContainer)` in `ZaapApp`).
- `DeliveryLogService` uses `modelContainer.mainContext` — the **same context**.
- However, `@Query` refreshes by subscribing to persistent store notifications triggered by `ModelContext.save()`. Even on the same context, inserts that are never saved do not trigger those notifications.

### Threading check — no issue

All five delivery services (`LocationDeliveryService`, `SleepDeliveryService`, `HeartRateDeliveryService`, `ActivityDeliveryService`, `WorkoutDeliveryService`) are `@MainActor`. Every call to `deliveryLog.record()` therefore happens on the main actor, which is the correct isolation for `mainContext`. No threading fix required.

### Race condition check — no issue

`startServices()` (called via `.task {}` when the window appears) calls `configure()` before `start()` for every service. Since all services initialize with `NullDeliveryLog()` and only activate on `start()`, there is no window where a delivery can happen before the real log is injected.

## Fix Applied

**`DeliveryLogService.swift` — Option A: add `try? context.save()` after `context.insert()`**

```swift
// Before
func record(dataType: DeliveryDataType, timestamp: Date, success: Bool, errorMessage: String? = nil) {
    let record = DeliveryRecord(dataType: dataType, timestamp: timestamp, success: success, errorMessage: errorMessage)
    context.insert(record)
}

// After
func record(dataType: DeliveryDataType, timestamp: Date, success: Bool, errorMessage: String? = nil) {
    let record = DeliveryRecord(dataType: dataType, timestamp: timestamp, success: success, errorMessage: errorMessage)
    context.insert(record)
    try? context.save()
}
```

`try?` is intentional: save failures are non-fatal for delivery logging (the webhook send already succeeded) and will surface naturally via Xcode diagnostics. A future improvement could add error logging via `Logger`.

## Build Verification

```
** BUILD SUCCEEDED **
```

Target: `Zaap` scheme, `iPhone 17 Pro` simulator.
