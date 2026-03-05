# zaap-x9d: STT transcript resets mid-speech after ~3 exchanges

## Summary
Fixed STT transcript resetting mid-speech by increasing silence threshold from 1.0 to 3.0 seconds to allow natural speech pauses.

## Changes Made
- VoiceEngine: Increased silenceThreshold from 1.0 to 3.0 seconds
- Updated test in VoiceEngineTests to verify new threshold

## Verification
- xcodebuild test: Tests SUCCEEDED
- Manual verification: Transcript now persists through natural speech pauses without resetting mid-utterance