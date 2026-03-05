# zaap-9bu: First mic activation does not start conversation

## Summary
Fixed first mic tap not starting conversation by updating VoiceChatView to call coordinator.tapMic() instead of viewModel.tapMic().

## Changes Made
- VoiceChatView: Changed button action to coordinator.tapMic() to enable proper state management and voice engine control
- Added test in VoiceChatCoordinatorTests for tapMic in speaking state to interrupt TTS

## Verification
- xcodebuild test: Tests SUCCEEDED
- Manual verification: First tap on mic button now starts listening and conversation