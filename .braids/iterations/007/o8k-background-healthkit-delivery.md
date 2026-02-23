# zaap-o8k — True Background HealthKit Delivery

## Problem

Heart rate, activity, workout, and sleep data are only POSTed when the app is launched
(`deliverDailySummary()` called in each service's `start()`). During a full-day hike/flight
with the phone backgrounded, **zero health data was sent** — only location (which has a
dedicated background mode via `CLLocationManager`).

`HealthKitObserverService` already exists and calls `enableBackgroundDelivery` + registers
`HKObserverQuery`, but the observer callback does not actually trigger delivery. The
`ObserverDeliveryAdapter` wiring appears broken or untested.

## Goal

Health data (heart rate, activity, workout, sleep) is POSTed to `/hooks/*` as soon as
HealthKit records it — without the app being open or the user tapping anything.

## Required Changes

### 1. Fix ObserverDeliveryAdapter → DeliveryService wiring
`HealthKitObserverService` calls `deliveryDelegate?.deliverData(for: dataType)`.
Verify `ObserverDeliveryAdapter.deliverData()` actually calls the appropriate delivery service
method (e.g. `HeartRateDeliveryService.shared.deliverDailySummary()`). Add tests.

### 2. Background URLSession for health webhook POSTs
Switch `WebhookClient` (or create a separate background client) to use
`URLSessionConfiguration.background(withIdentifier: "co.airworthy.zaap.health")`.
Background sessions complete even when the app is suspended or killed by iOS.

### 3. HKObserverQuery completionHandler ordering
The `completionHandler` passed to the `HKObserverQuery` handler **must** be called only
after the background URLSession task is enqueued — not before. Calling it early tells iOS
the work is done and it may suspend the app before the network request fires.

### 4. Background mode entitlements
Verify `Info.plist` has `UIBackgroundModes` including `fetch` and `processing`
(in addition to `location` which already exists). May need `BGTaskScheduler` registration
for longer-running background work.

### 5. Remove single-shot on-launch delivery (optional)
`deliverDailySummary()` called in `start()` is a workaround for missing background delivery.
Once observers work reliably, remove the on-launch send to avoid duplicate POSTs.

### 6. Test with HealthDataSeeder
Use the simulator's Developer section → "Seed Health Data" to generate HR/sleep/activity,
then verify hooks fire in the background using the mock-gateway.

## Constraints
- TDD: tests before implementation
- No third-party deps (Apple frameworks only)
- Build verify only — do NOT run `xcodebuild test`
- Do NOT push to TestFlight

## Priority
P1 — confirmed broken by real-world usage (Sedona hike, Feb 22 2026)
