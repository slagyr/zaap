# Bead zaap-8qs: Delivery Deduplication

## Summary
Added last-delivered timestamp deduplication to all four health delivery services (HeartRate, Sleep, Activity, Workout) to prevent redundant data sends on observer callbacks and app launches.

## What Changed

### New Files
- **DeliveryAnchorStore.swift** — `DeliveryAnchorStoring` protocol + `UserDefaultsDeliveryAnchorStore` implementation + `NullDeliveryAnchorStore` (backward compat)
- **DeliveryAnchorStoreTests.swift** — 4 tests for the anchor store

### Modified Services
All four delivery services now accept an optional `anchorStore` parameter (defaults to `NullDeliveryAnchorStore` for backward compatibility):

- **HeartRateDeliveryService** — `deliverDailySummary()` skips if already delivered today
- **SleepDeliveryService** — `deliverLatest()` skips if already delivered today
- **ActivityDeliveryService** — `deliverLatest()` skips if already delivered today
- **WorkoutDeliveryService** — `deliverLatest()` passes anchor as `from` date to `fetchRecentSessions`, skips POST if no new sessions

### Dedup Rules
- **Daily data** (HR, Sleep, Activity): Same-calendar-day check via `Calendar.current.isDateInToday(anchor)`
- **Workouts**: Anchor used as query start date; empty results = skip
- **sendNow**: Always bypasses dedup (manual trigger)
- **Anchor update**: Only on successful POST (failures don't update anchor)

### Tests Added
23 new tests across all service test files covering:
- Skip when already delivered today
- Proceed when anchor is from yesterday
- Anchor updated on success
- Anchor NOT updated on failure
- sendNow bypasses dedup

## Commit
`1f25d3e` — "Add last-delivered timestamp deduplication to delivery services (zaap-8qs)"
