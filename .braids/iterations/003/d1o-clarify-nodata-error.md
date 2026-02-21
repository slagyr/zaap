# zaap-d1o: WorkoutReader — clarify noData error message

## Status: Blocked (build broken by unrelated uncommitted work)

## Changes Made

### WorkoutReader.swift (line 30)
- **Before:** `"No workout data found for the requested period"`
- **After:** `"No workouts found in the last 24 hours"`

### WorkoutReaderTests.swift (line 30)
- Updated test assertion to match new message

## Blocker

The project won't compile due to other in-progress uncommitted work:
- `MainTabView.swift` references `VoiceChatView`, `GatewayBrowserViewModel`, `NWGatewayBrowser`
- `ZaapApp.swift` references `ObserverDeliveryAdapter`, `HealthKitObserverService`

Cannot run tests to verify. Once the build is fixed, this bead can be re-claimed and closed after test verification.
