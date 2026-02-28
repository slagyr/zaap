# zaap-6vv: Voice tab filters to selected session only

## Problem
The gateway broadcasts chat events for all sessions. VoiceChatCoordinator processed every incoming chat event regardless of which session it belonged to, causing messages from Discord channels (and other sessions) to appear in the voice chat transcript.

## Solution
Added session key filtering at two levels in `VoiceChatCoordinator.swift`:

1. **`handleGatewayEvent`** — Top-level guard: if a payload contains a `sessionKey` field that doesn't match `self.sessionKey`, the event is rejected immediately (covers legacy token/done events too).

2. **`handleChatEvent`** — Strict guard: requires `sessionKey` to be present in the payload AND match `self.sessionKey`. Events without a session key are ignored (safe default).

## Files Changed
- `Zaap/Zaap/VoiceChatCoordinator.swift` — Added session key filtering guards
- `Zaap/ZaapTests/VoiceChatCoordinatorTests.swift` — Added 5 new tests for session filtering, updated 1 existing test

## Tests Added
- `testChatEventMatchingSessionKeyIsProcessed` — Correct session events are processed
- `testChatEventDifferentSessionKeyIsIgnored` — Wrong session events are dropped
- `testChatEventWithNoSessionKeyIsIgnored` — Events missing sessionKey are dropped
- `testChatFinalEventDifferentSessionKeyDoesNotSpeak` — Final events from wrong session don't trigger TTS
- `testLegacyTokenEventWithDifferentSessionKeyIsIgnored` — Legacy token events filtered too
