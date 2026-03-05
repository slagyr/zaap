# Standardize Webhook Payload Field Names

## Summary
Updated HeartRateReader, HRVReader, and SpO2Reader to use standardized JSON field names (min/max/avg/resting/sampleCount) for webhook payloads while keeping Swift property names readable.

## Changes Made

### HeartRateReader.swift
- Added CodingKeys enum to map minBPM → "min", maxBPM → "max", avgBPM → "avg", restingBPM → "resting"

### HRVReader.swift
- Added CodingKeys enum to map minSDNN → "min", maxSDNN → "max", avgSDNN → "avg", restingSDNN → "resting"

### SpO2Reader.swift
- Added CodingKeys enum to map minPercentage → "min", maxPercentage → "max", avgPercentage → "avg", restingPercentage → "resting"

### Tests Added
- HeartRateReaderTests/testWebhookPayloadFieldNames: Verifies JSON encoding uses correct field names
- HRVReaderTests/testWebhookPayloadFieldNames: Verifies JSON encoding uses correct field names
- SpO2ReaderTests/testWebhookPayloadFieldNames: Verifies JSON encoding uses correct field names

## Implementation Details
- CodingKeys allows separation of Swift property names (readable) from JSON keys (standardized)
- sampleCount field unchanged as it already matches gateway expectations
- All data structs remain Codable and backward compatible for Swift usage

## Verification
### Tests
```
$ xcodebuild test -scheme Zaap -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
Test Suite 'HeartRateReaderTests' passed:
- testWebhookPayloadFieldNames ✅
Test Suite 'HRVReaderTests' passed:
- testWebhookPayloadFieldNames ✅
Test Suite 'SpO2ReaderTests' passed:
- testWebhookPayloadFieldNames ✅
All tests passed.
```

### JSON Output Example
HeartRateData now encodes as:
```json
{
  "min": 60,
  "max": 120,
  "avg": 80,
  "resting": 65,
  "sampleCount": 100
}
```

This matches the gateway message templates and ensures consistent field naming across all health data webhooks.