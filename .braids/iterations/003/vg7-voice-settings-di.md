# Voice Uses Settings TTS Voice via DI (zaap-vg7)

## Summary

Refactored `ResponseSpeaker` to receive `SettingsManager` via dependency injection instead of accessing the `SettingsManager.shared` singleton directly. Voice chat now automatically uses the TTS voice selected in Settings without any separate selection mechanism.

## Changes

### ResponseSpeaker.swift
- Added `private let settings: SettingsManager` property
- Updated init: `init(synthesizer:settings:)` with default `settings: .shared`
- `speakImmediate()` reads `settings.ttsVoiceIdentifier` instead of `SettingsManager.shared.ttsVoiceIdentifier`
- Existing callers unaffected (default parameter preserves backward compatibility)

### TestDoubles.swift
- Added `spokenUtterances: [AVSpeechUtterance]` to `MockSpeechSynthesizer` for voice verification in tests

### ResponseSpeakerTests.swift
- `testSpeakImmediateUsesVoiceIdentifierFromSettings` — verifies injected voice ID is used
- `testSpeakImmediateUsesSystemDefaultWhenVoiceIdentifierEmpty` — verifies en-US fallback
- `testSpeakImmediatePicksUpVoiceChangeBetweenCalls` — verifies dynamic voice changes are picked up

## Design

The default parameter `settings: .shared` means:
- Production code (VoiceChatView) works unchanged — no wiring needed
- Tests can inject isolated `SettingsManager(defaults:)` instances
- Voice selection in Settings is automatically reflected in voice chat
