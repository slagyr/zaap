# Deliverable: Remove Eager deliverLatest() from start() (zaap-rcu)

## Summary

Removed eager `deliverLatest()` / `deliverDailySummary()` calls from the `start()` method of all four delivery services. Previously, every app launch triggered an immediate batch of health data delivery. Now `start()` only validates configuration — delivery only fires when HealthKitObserverService triggers a callback.

## Changes

### Implementation (4 files)
- **SleepDeliveryService.swift** — Removed `deliverLatest()` call from `start()`
- **ActivityDeliveryService.swift** — Removed `deliverLatest()` call from `start()`
- **WorkoutDeliveryService.swift** — Removed `deliverLatest()` call from `start()`
- **HeartRateDeliveryService.swift** — Removed entire `Task` block (authorization + `deliverDailySummary()`) from `start()`

### Tests (4 files)
- Replaced `testStartDeliversWhenEnabled` with `testStartDoesNotDeliverEagerly` in all four test files
- Removed `testStartLogsErrorOnAuthorizationFailure` from HeartRateDeliveryServiceTests (no longer applicable)
- All tests pass (0 failures across all suites)

## Commit
`15189fb` — Remove eager deliverLatest() calls from start() (zaap-rcu)
