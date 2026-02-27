# zaap-9ou: Clean up pairing view

## Summary

All three improvements from this bead were already implemented in prior commits:

1. **Show pairing view immediately** — `VoiceChatView` already defaults `isPaired = false` and checks in `onAppear` (commit `12781d5`)
2. **Handle NOT_PAIRED response** — `VoiceChatCoordinator.gatewayDidFailWithError` already fires `needsRepairingPublisher` on any `.challengeFailed` error, which flips the view to pairing (commit `b56284a`)
3. **Remove Copy Device ID button** — The button and `copiedDeviceId` state were already removed from `VoicePairingView`

## Tests

Existing tests already cover the re-pairing flow:
- `testChallengeFailedSendsNeedsRepairing` — verifies `pairing_required` triggers re-pair
- `testNotPairedErrorSendsNeedsRepairing` — verifies `pairing_required:<id>` triggers re-pair

## Build

`xcodebuild build` and relevant tests pass.
