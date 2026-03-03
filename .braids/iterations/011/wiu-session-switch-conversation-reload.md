# zaap-wiu: Session switch while mic active — conversation log doesn't reload

## Problem
When switching sessions while the mic is active, the conversation log showed stale messages from the previous session. The voice engine, speaker, and mic restart tasks weren't cleaned up on session switch.

## Solution
Enhanced `VoiceChatCoordinator.updateSessionKey()` to cleanly reset voice state when a session switch occurs while active:

1. **Stop voice engine** — prevents orphaned audio capture
2. **Interrupt speaker** — stops any in-flight TTS from the old session
3. **Cancel mic restart task** — prevents stale restart from firing
4. **Clear VM partial state** — clears partialTranscript and responseText via `loadPreviewMessages`
5. **Reset VM to idle** — ensures clean state before new session loads
6. **Schedule mic restart** — if conversation mode was on, restarts mic after delay for the new session

The conversation log itself is already reloaded by the view's `.onChange(of: sessionPicker.previewMessages)` handler, which calls `viewModel.loadPreviewMessages()`. The coordinator fix ensures voice pipeline state is clean so old-session responses don't leak in.

## Files Changed
- `Zaap/Zaap/VoiceChatCoordinator.swift` — `updateSessionKey()` now handles active session cleanup
- `Zaap/ZaapTests/VoiceChatCoordinatorTests.swift` — 8 new tests covering session switch scenarios

## Tests Added
- `testUpdateSessionKeyWhileActiveStopsVoiceEngine`
- `testUpdateSessionKeyWhileActiveInterruptsSpeaker`
- `testUpdateSessionKeyWhileActiveRestartsMicAfterDelay`
- `testUpdateSessionKeyWhileActiveAndConversationModeOffDoesNotRestartMic`
- `testUpdateSessionKeyWhileInactiveDoesNotStopVoiceEngine`
- `testUpdateSessionKeyClearsViewModelPartialState`
- `testUpdateSessionKeyTransitionsViewModelToIdleBeforeRestart`
- `testOldSessionResponseIgnoredAfterSessionSwitch`
