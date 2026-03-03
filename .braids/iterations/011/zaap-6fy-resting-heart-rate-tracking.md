# Resting Heart Rate Tracking Implementation

## Overview
Added complete resting heart rate tracking functionality to the Zaap app, including:

- **ObservedHealthDataType.restingHeartRate** enum case
- **RestingHeartRateReader** class for HealthKit data access
- **RestingHeartRateDeliveryService** for webhook delivery
- **DeliveryDataType.restingHeartRate** enum case
- Settings UI toggle for resting heart rate tracking
- Background observer support for automatic delivery

## Files Added

### Core Implementation
- `Zaap/Zaap/RestingHeartRateReader.swift` - Reads resting HR data from HealthKit
- `Zaap/Zaap/RestingHeartRateDeliveryService.swift` - Posts summaries to `/resting-heart-rate` webhook endpoint

### Tests
- `Zaap/ZaapTests/RestingHeartRateReaderTests.swift` - Unit tests for data model
- `Zaap/ZaapTests/RestingHeartRateDeliveryServiceTests.swift` - Full service integration tests

### Configuration
- Updated `HealthKitObserverService` to support resting HR observer queries
- Added `restingHeartRateTrackingEnabled` setting in `SettingsManager`
- Wired into `ObserverDeliveryAdapter` for background delivery
- Added UI toggle in `SettingsView` with send-now capability

## Technical Details

### Data Model
```swift
struct DailyRestingHRSummary: Codable, Sendable {
    let date: String           // YYYY-MM-DD
    let restingBPM: Double
    let sampleCount: Int
    let samples: [RestingHRSample]
}

struct RestingHRSample: Codable, Sendable {
    let bpm: Double
    let timestamp: Date
}
```

### Webhook Endpoint
- Path: `/hooks/resting-heart-rate`
- Payload: `DailyRestingHRSummary` JSON

### HealthKit Integration
- Identifier: `HKQuantityType.quantityType(forIdentifier: .restingHeartRate)`
- Observer frequency: Hourly (background delivery)
- Authorization: Requested alongside regular heart rate

### Background Delivery
- Observes for new resting HR data writes from Apple Watch/other apps
- Automatically fetches and delivers latest daily summary when changes detected
- Respects daily deduplication (won't deliver same data twice in one day)

## Testing
- Full TDD implementation with comprehensive test coverage
- Tests for success/failure paths, deduplication, authorization, configuration
- Mock implementations for dependency injection
- Integration with existing delivery infrastructure

## Build Status
✅ Compiles successfully  
✅ All tests pass  
✅ Wired into app services  
✅ Settings UI updated  
✅ Background observers configured

## Acceptance Criteria Met
- [x] Added ObservedHealthDataType for resting HR
- [x] Implemented delivery service with webhook posting
- [x] Created `/hooks/resting-heart-rate` route integration
- [x] Background observer support for automatic delivery
- [x] Settings UI toggle with send-now functionality
- [x] Full test coverage following TDD practices
- [x] Follows existing app patterns and conventions
