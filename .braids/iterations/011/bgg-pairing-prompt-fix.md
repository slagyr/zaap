# zaap-bgg: Pairing prompt appears every launch despite being already paired

## Root Cause

`VoiceChatCoordinator.gatewayDidFailWithError` treated ALL `challengeFailed` errors as pairing failures, firing `needsRepairingPublisher` which called `clearPairing()` and wiped the token. Any transient error (timeout, server hiccup) during the challenge handshake would destroy valid pairing state.

## Fix

Changed the coordinator to only trigger re-pairing when the error message specifically indicates a pairing issue (`pairing_required` or `NOT_PAIRED` prefix). Non-pairing challenge failures no longer wipe the token.

### Files Changed
- `Zaap/Zaap/VoiceChatCoordinator.swift` — Filter `challengeFailed` by message prefix
- `Zaap/ZaapTests/VoiceChatCoordinatorTests.swift` — Added `testNonPairingChallengeFailedDoesNotTriggerRepairing`

## Verification
- 452 tests pass, 0 failures
- Existing pairing tests still pass
- New test confirms transient errors don't trigger re-pairing
