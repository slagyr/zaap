# zaap-g27: Fix respiratory rate and resting HR payload field names

## Problem
Two webhook payload structs used Swift property names as JSON keys, which didn't match the gateway message template expectations:

1. `RespiratoryRateReader.DailyRespiratoryRateSummary` — encoded `minRate`, `maxRate`, `avgRate` but gateway templates expect `min`, `max`, `avg`
2. `RestingHeartRateReader.DailyRestingHRSummary` — encoded `restingBPM` but gateway template expects `resting`

## Fix
Added `CodingKeys` enums to both structs, mapping Swift property names to gateway-expected JSON keys:

### RespiratoryRateReader.DailyRespiratoryRateSummary
- `minRate` → `"min"`
- `maxRate` → `"max"`
- `avgRate` → `"avg"`

### RestingHeartRateReader.DailyRestingHRSummary
- `restingBPM` → `"resting"`

## Files changed
- `Zaap/Zaap/RespiratoryRateReader.swift` — added CodingKeys enum
- `Zaap/Zaap/RestingHeartRateReader.swift` — added CodingKeys enum
- `Zaap/ZaapTests/RespiratoryRateReaderTests.swift` — new file with encode/decode tests verifying JSON key names
- `Zaap/ZaapTests/RestingHeartRateReaderTests.swift` — updated with encode/decode tests verifying JSON key names
- `Zaap/Zaap.xcodeproj/project.pbxproj` — added new test file references

## Test results
- Main target: **BUILD SUCCEEDED**
- My test files compile without errors
- Pre-existing compilation failures in unrelated test files (HeartRateReaderTests, VoiceChatCoordinatorTests, HRVReaderTests) prevent the test target from running — these are not related to this bead
