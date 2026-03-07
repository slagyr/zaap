# zaap-lzy: Re-deliver health telemetry when new samples arrive

## Summary

Replaced the 'already delivered today' date-based deduplication with sampleCount-based deduplication for health telemetry delivery services. Now skips delivery only if the current sampleCount <= last delivered count, ensuring re-delivery when Watch syncs bring new samples, while preventing duplicates.

Applied to: HeartRate, HRV, SpO2, RestingHeartRate, RespiratoryRate delivery services.

Kept Activity and Sleep on date-based deduplication as they lack sampleCount in summaries.

## Changes

- **DeliveryAnchorStore.swift**: Added lastSampleCount/setLastSampleCount to protocol and implementations.

- **HeartRateDeliveryService.swift**: Changed skip logic to compare sampleCount, update lastSampleCount on delivery.

- **HRVDeliveryService.swift**: Same.

- **SpO2DeliveryService.swift**: Same.

- **RestingHeartRateDeliveryService.swift**: Same.

- **RespiratoryRateDeliveryService.swift**: Same.

## Verification

- xcodebuild test -scheme Zaap -destination 'platform=iOS Simulator,name=iPhone 17 Pro' passes

- Tests updated to verify new sampleCount-based deduplication logic