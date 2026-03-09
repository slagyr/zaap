# Improve 'no data' error messages to specify the time period

## Summary
Updated error messages in all health data readers to specify the time period instead of the generic "No data for the period requested". Now messages include the specific window like "No heart rate data for today" or "No sleep data for the past 24 hours".

## Details
Modified the following files to change the error message thrown when no data is found for the requested period:

- HeartRateReader.swift: "No heart rate data for today"
- HRVReader.swift: "No HRV data for today" 
- SpO2Reader.swift: "No SpO2 data for today"
- RespiratoryRateReader.swift: "No respiratory rate data for today"
- RestingHeartRateReader.swift: "No resting heart rate data for today"
- ActivityReader.swift: "No activity data for today"
- SleepDataReader.swift: "No sleep data for the past 24 hours"

## Verification
Ran `xcodebuild test -scheme Zaap -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` — all tests pass.

## Assets
None.