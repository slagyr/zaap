# zaap-s5u: Fix Barge-In During Long TTS Responses

## Problem

While the agent was speaking a long TTS response, the user could not interrupt playback — neither by tapping the mic nor by speaking. The user had to wait until TTS finished before interacting.

**Root cause:** Two issues combined:

1. **Response bubble disappeared instantly during TTS.** In `handleChatEvent` for "final", `viewModel.handleResponseComplete()` was called immediately after `speaker.speakImmediate()`, clearing `responseText` and setting `viewModel.state` to `.idle`. This removed the response bubble (which had the barge-in tap gesture) and hid the "speaking" status indicator — all while TTS was still playing.

2. **Mic button toggled conversation mode instead of barging in.** During TTS, the mic button called `toggleConversationMode()` which killed the entire conversation session instead of doing a quick interrupt-and-resume.

## Fix

### VoiceChatCoordinator (core fix)

- **Deferred response completion:** Added `pendingResponseCompletion` flag. When a chat "final" event arrives and TTS is playing (`speaker.state == .speaking`), `handleResponseComplete()` is deferred until TTS finishes. This keeps `responseText` populated and `viewModel.state == .speaking` during playback, making the response bubble visible and tappable for barge-in.

- **Completion triggers:** `completePendingResponse()` helper is called from:
  - `speaker.onStateChange(.idle)` — TTS finished naturally
  - `bargeIn()` — user interrupted via tap
  - `handleUtteranceComplete()` — user spoke over TTS
  - `stopSession()` — session ended during TTS
  - `toggleConversationMode()` — conversation mode toggled off during TTS
  - `updateSessionKey()` — session switched during TTS

### VoiceChatView (mic button fix)

- **Mic button barge-in:** When `viewModel.state == .speaking` (TTS is playing), the mic button now calls `coordinator.bargeIn()` instead of `coordinator.toggleConversationMode()`. This interrupts TTS and immediately restarts the mic for the user to speak.

### Two barge-in affordances

Users now have two ways to interrupt TTS:
1. **Tap the response bubble** (existing `onTapGesture` — now works because the bubble stays visible)
2. **Tap the mic button** (new — triggers `bargeIn()` when state is `.speaking`)

## Tests Added

7 new tests in `VoiceChatCoordinatorTests` under "Barge-In: Deferred Response Completion During TTS (zaap-s5u)":

- `testChatFinalKeepsResponseBubbleVisibleDuringTTS` — responseText stays populated during TTS
- `testChatFinalCompletesResponseWhenTTSFinishes` — text moves to log when TTS finishes
- `testBargeInDuringTTSMovesResponseToLog` — barge-in commits text to log and transitions to listening
- `testViewModelStateSpeakingDuringTTSEnablesMicButtonBargeIn` — VM state is `.speaking` during TTS
- `testStopSessionDuringTTSCompletesResponse` — stopping session commits text to log
- `testToggleConversationModeOffDuringTTSCompletesResponse` — toggling off commits text to log
- `testNewUtteranceDuringTTSCompletesOldResponse` — speaking over TTS commits old response to log

2 existing tests updated to simulate TTS finishing before checking conversation log (zaap-9nl tests).

## Files Changed

- `Zaap/Zaap/VoiceChatCoordinator.swift` — deferred completion logic, `completePendingResponse()` helper
- `Zaap/Zaap/VoiceChatView.swift` — mic button barge-in routing
- `ZaapTests/VoiceChatCoordinatorTests.swift` — 7 new tests, 2 updated tests

## Verification

All tests pass: full test suite (`xcodebuild test -scheme Zaap`) — 0 failures.
