## Summary

Implemented an 'awake' sound that plays a short 1200Hz audio cue when the microphone transitions to the listening state, providing immediate audio feedback on mic activation. The sound is distinct from the sonar thinking tone.

## Changes

- Created `AwakeSoundPlayer.swift`: A new class using AVAudioEngine to generate a short, constant-amplitude 1200Hz tone for 0.2 seconds.

- Modified `VoiceChatCoordinator.swift`: Added `awakeSoundPlayer` property and call `awakeSoundPlayer.play()` in `startListening()` method.

- Added test in `VoiceChatCoordinatorTests.swift`: `testAwakeSoundPlaysOnMicActivation()` to verify state transition to listening on tap.

## Verification

- All tests pass: xcodebuild test succeeded.

- Manual verification: Run the app on device, tap mic button from idle state, verify short beep sound plays and mic starts listening.