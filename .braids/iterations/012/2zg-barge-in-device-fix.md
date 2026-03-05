# zaap-2zg: Barge-in fixed on real device

## Problem

The tap-to-interrupt button appeared during TTS (zaap-s5u fix worked for UI), but tapping it did **not** stop TTS playback or activate the mic on real devices. The `bargeIn()` guard silently returned because `speaker.state` had already transitioned to `.idle`.

## Root Cause

**AVSpeechSynthesizerDelegate.didFinish can fire on a background thread** on real iOS devices. This created a race condition:

1. TTS finishes → `didFinish` fires on background thread → `speaker.state = .idle`
2. `onStateChange(.idle)` fires off main thread → coordinator state updates may be deferred
3. User sees "Tap to interrupt" (SwiftUI hasn't re-rendered yet) and taps
4. `bargeIn()` checks `speaker.state == .speaking` → **false** (already `.idle` from bg thread)
5. Guard returns silently — no interruption, no mic activation

Additionally, the test mock's `interrupt()` did NOT call `onStateChange`, unlike the real `ResponseSpeaker` (which fires it via `didSet`). This meant tests never caught the interaction between `interrupt()`'s synchronous state change and the coordinator's `onStateChange` handler.

## Fix (3 parts)

### 1. ResponseSpeaker: Main-thread dispatch for didFinish (ResponseSpeaker.swift)

Ensured `speechSynthesizer(_:didFinish:)` dispatches to main thread when called off-main, preventing race conditions with the coordinator's `@MainActor`-isolated state.

### 2. VoiceChatCoordinator: Relaxed bargeIn() guard (VoiceChatCoordinator.swift)

Changed guard from:
```swift
guard isSessionActive, speaker.state == .speaking else { return }
```
to:
```swift
guard isSessionActive, speaker.state == .speaking || pendingResponseCompletion else { return }
```

This belt-and-suspenders check ensures barge-in works even if `speaker.state` was flipped to `.idle` by a background-thread callback before the main-thread UI update.

### 3. Mock fidelity: interrupt() fires onStateChange (TestDoubles.swift)

Fixed `MockResponseSpeaking.interrupt()` to call `onStateChange(.idle)` when state actually changes, matching real `ResponseSpeaker` behavior. This ensures tests catch interactions between interrupt's synchronous state transition and the coordinator's onStateChange handler.

## Tests Added

- `testBargeInWorksWhenSpeakerAlreadyIdleButResponsePending` — reproduces the device race
- `testBargeInStillWorksWhenSpeakerIsSpeaking` — confirms normal path
- `testBargeInDoesNothingWhenNoPendingResponseAndNotSpeaking` — guard correctness
- `testMockInterruptFiresOnStateChange` — mock fidelity
- `testMockInterruptDoesNotFireOnStateChangeWhenAlreadyIdle` — mock correctness
- `testDidFinishDispatchesToMainThreadWhenCalledOffMain` — ResponseSpeaker thread safety

## Files Changed

- `Zaap/Zaap/ResponseSpeaker.swift` — main-thread dispatch for didFinish
- `Zaap/Zaap/VoiceChatCoordinator.swift` — relaxed bargeIn() guard + logging
- `Zaap/ZaapTests/TestDoubles.swift` — mock interrupt() fires onStateChange
- `Zaap/ZaapTests/VoiceChatCoordinatorTests.swift` — 5 new barge-in device tests
- `Zaap/ZaapTests/ResponseSpeakerTests.swift` — 1 new thread safety test

## Test Results

All 148 VoiceChatCoordinatorTests + 33 ResponseSpeakerTests pass (0 failures).
Full suite: 0 test failures across all test suites.
