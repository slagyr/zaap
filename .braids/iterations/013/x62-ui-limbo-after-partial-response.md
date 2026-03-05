# UI Limbo After Partial Response

## Summary
Fixed UI getting stuck in limbo state after partial responses by properly handling state transitions and allowing interruption of thinking state.

## Changes Made

### VoiceChatCoordinator.swift
- **handlePartialResponse**: Added check to prevent redundant state changes to speaking when already speaking
- **tapMic**: Added case for .thinking state to allow user interruption - stops listening and returns to listening state
- **Added missing gateway message handlers**: handleGatewayMessage, handleGatewayPartialMessage, handleGatewayError to properly manage state transitions

### VoiceEngine.swift
- **stopListening**: Added `isListening = false` to properly track listening state

### VoiceChatCoordinatorTests.swift
- **testPartialResponseHandling**: Added test to verify partial responses transition to speaking state and start TTS
- **testPartialResponseCancellation**: Added test to verify user can interrupt partial responses

## Root Cause
The limbo state occurred because:
1. Partial response arrived while in thinking state
2. State transitioned to speaking, but TTS never started properly
3. User couldn't interrupt because tapMic didn't handle thinking state
4. Thinking tone kept looping because state machine was stuck

## Verification
### Tests
```
$ xcodebuild test -scheme Zaap -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
Test Suite 'VoiceChatCoordinatorTests' passed:
- testPartialResponseHandling ✅
- testPartialResponseCancellation ✅
All tests passed.
```

### Manual Testing Steps
1. Start conversation (mic tap)
2. Speak a query that triggers partial response
3. Verify TTS starts immediately when partial response arrives
4. Tap mic during thinking or speaking - should interrupt and return to listening
5. No more limbo states or looping thinking tones

## State Machine Improvements
- Thinking state is now interruptible by user
- Partial responses properly transition states
- All gateway message types have dedicated handlers
- VoiceEngine tracks listening state accurately