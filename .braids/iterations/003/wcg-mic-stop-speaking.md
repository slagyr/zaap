# zaap-wcg: Mic button off should stop both listening and speaking

## Problem
When the user tapped the mic button to turn it off, `stopSession()` called `speaker.interrupt()` to stop current speech, but late-arriving gateway responses (both `chat` "final" events and legacy `token`/`done` events) could restart TTS by calling `speaker.bufferToken()` and `speaker.flush()` — because these code paths didn't check whether the session was still active.

## Fix
Added `isActive` guards around all `speaker.bufferToken()` and `speaker.flush()` calls in:
- `handleChatEvent` "final" case
- `handleGatewayEvent` legacy "token" case
- `handleGatewayEvent` legacy "done" case

View model updates still happen (so the response text appears in the UI), but no audio is played after the user stops the session.

## Tests Added
- `testStopSessionPreventsIncomingResponseFromSpeaking` — verifies that a "final" chat event arriving after `stopSession()` does not trigger speaker
- `testStopSessionPreventsLegacyTokensFromSpeaking` — verifies that legacy token/done events arriving after `stopSession()` do not trigger speaker

## Files Changed
- `Zaap/Zaap/VoiceChatCoordinator.swift` — added `isActive` guards
- `Zaap/ZaapTests/VoiceChatCoordinatorTests.swift` — added 2 tests
