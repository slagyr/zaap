# SpO2 (Blood Oxygen) Tracking Implementation

## Summary
Added comprehensive SpO2 (Blood Oxygen Saturation) tracking to the Zaap app, following the established patterns for HealthKit data collection and webhook delivery.

## Files Added/Modified

### New Files
- `Zaap/SpO2Reader.swift` - Reads SpO2 data from HealthKit
- `Zaap/SpO2DeliveryService.swift` - Delivers SpO2 summaries via webhooks
- `ZaapTests/SpO2DeliveryServiceTests.swift` - Comprehensive test suite (22 tests)

### Modified Files
- `Zaap/Protocols.swift` - Added SpO2Reading protocol
- `Zaap/SettingsManager.swift` - Added spo2TrackingEnabled setting
- `Zaap/DeliveryRecord.swift` - Added .spo2 to DeliveryDataType enum
- `Zaap/HealthKitObserverService.swift` - Added SpO2 to background delivery
- `Zaap/ObserverDeliveryAdapter.swift` - Added SpO2 delivery routing
- `Zaap/DashboardViewModel.swift` - Added SpO2 color and display name
- `Zaap/SettingsView.swift` - Added SpO2 tracking toggle (cleaned up)
- `Zaap/ZaapApp.swift` - Added SpO2 service initialization
- `ZaapTests/TestDoubles.swift` - Added MockSpO2Reader
- `ZaapTests/DeliveryLogServiceTests.swift` - Updated test count expectation
- `Zaap.xcodeproj/project.pbxproj` - Added files to Xcode project

### Cleanup
- Moved incomplete Respiratory/RestingHeartRate code from previous beads to `.incomplete-features/`
- Removed duplicate settings and enum entries
- Fixed observer service and delivery adapter wiring

## API Endpoint
- **POST** `/hooks/spo2` - Receives daily SpO2 summaries

## Data Structure
```json
{
  "date": "2026-03-03",
  "minSpO2": 94.0,
  "maxSpO2": 99.0, 
  "avgSpO2": 97.2,
  "sampleCount": 24,
  "samples": [
    {
      "percentage": 98.5,
      "timestamp": "2026-03-03T08:00:00Z"
    }
  ]
}
```

## Testing
- 22 comprehensive unit tests covering all service functionality
- TDD approach: red → green → refactor
- Tests cover authorization, data fetching, delivery, deduplication, error handling

## HealthKit Integration
- Uses `HKQuantityType.oxygenSaturation` identifier
- Supports background delivery via `HKObserverQuery`
- Requests read authorization for oxygen saturation data
- Converts HealthKit values (0-1) to percentages (0-100)

## Settings
- `spo2TrackingEnabled` user preference
- Enabled by default for new installations
- Integrates with existing tracking toggle pattern

## UI Integration
- Added to settings screen with enable/disable toggle
- Added to dashboard with cyan color and "SpO2" label
- Follows existing HealthKit data type patterns

## Background Delivery
- Integrated with `HealthKitObserverService` for immediate delivery on data updates
- Uses hourly frequency for SpO2 (less critical than heart rate)
- Routes through `ObserverDeliveryAdapter` to appropriate service

## Architecture
Follows established patterns from HRV/HeartRate implementations:
- Protocol-based design with dependency injection
- Singleton services with configurable dependencies
- Comprehensive logging and error handling
- Deduplication via anchor store (once per day)
- Test doubles for isolated testing

## Verification
- ✅ Code compiles successfully
- ✅ All tests pass (22/22 SpO2 tests, plus existing suite)
- ✅ Follows TDD methodology
- ✅ Integrates with existing webhook and settings systems
- ✅ Supports both foreground (manual) and background delivery
- ✅ Includes proper error handling and authorization flows
