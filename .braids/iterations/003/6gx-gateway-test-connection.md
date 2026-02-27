# zaap-6gx: Add Test Connection button to also test gateway bearer token connection

## Summary
Extended the existing "Test Connection" button in Settings to test both the webhook endpoint AND the gateway bearer token connection in parallel.

## Changes

### New Files
- **`Zaap/Zaap/GatewayTestService.swift`** — Service that tests gateway connectivity by sending an HTTP GET to `/health` on the gateway hostname with the gateway bearer token as Authorization header. Includes `URLSessionProtocol` abstraction for testability.
- **`Zaap/ZaapTests/GatewayTestServiceTests.swift`** — 6 test cases covering: success, empty hostname, empty token, server error (401), network error, and localhost HTTP scheme. Includes `MockURLSessionProtocol` test double.

### Modified Files
- **`Zaap/Zaap/SettingsView.swift`** — Updated `runTest()` to run both webhook and gateway tests concurrently using `async let`. Added `gatewayTestResult` state and separate result display rows showing "Webhook: OK/Failed" and "Gateway: OK/Failed".
- **`Zaap/Zaap.xcodeproj/project.pbxproj`** — Added new files to both main and test targets.

## Notes
- Test build was already broken before this bead due to `GatewaySession` type not being found in `VoiceChatCoordinator.swift` (pre-existing issue). Main target builds clean. Tests are structurally correct but couldn't be executed.
