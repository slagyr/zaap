# zaap-45i: Play thinking/processing sound while awaiting AI response

## Summary
Integrated ThinkingSoundPlayer into VoiceChatCoordinator so a subtle audio tone plays while the app awaits an AI response.

## Changes
- Added `thinkingSoundPlayer` optional parameter to VoiceChatCoordinator
- Start thinking sound on utterance complete, stop on: speaker starts, chat error, chat final, session stop
- Wired SystemThinkingSoundPlayer into production VoiceChatView
- Fixed pre-existing SettingsView build error (Respiratory Rate row missing params)
- 5 new coordinator integration tests, all passing

## Acceptance Criteria — all met
- [x] Thinking sound starts when request sent to gateway
- [x] Stops when TTS begins or error occurs
- [x] Bundled (generated programmatically, no asset files)
- [x] No audio session conflicts (separate AVAudioEngine)
- [x] Subtle volume (amplitude 0.08)
