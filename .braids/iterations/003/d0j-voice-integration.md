# Voice Integration — Wire VoiceEngine → GatewayConnection → ResponseSpeaker

## Summary

Wired up the full voice pipeline and added gateway pairing UI to Settings.

## What Was Done

### VoiceChatCoordinator (new)
- Coordinates VoiceEngine, GatewayConnection, ResponseSpeaker, and VoiceChatViewModel
- VoiceEngine utterance → `sendVoiceTranscript()` to gateway with session key
- Gateway `chat.event` tokens → ResponseSpeaker `bufferToken()` + ViewModel state updates
- Gateway `chat.event` done → `flush()` speaker + complete response + resume listening
- Interrupt handling: if user speaks while TTS is playing, calls `speaker.interrupt()`
- Session management: `startSession(gatewayURL:)` / `stopSession()` with unique session keys

### PairingViewModel (new)
- Manages gateway pairing state: address entry, connect, paired status, unpair
- Builds WSS URL from hostname (defaults port 18789) or accepts full URL
- Persists gateway URL via NodePairingManager keychain storage
- GatewayConnectionDelegate for connection status updates

### PairingSectionView (new)
- Settings section showing: gateway address field, pair button, paired status with connection badge
- Unpair button (destructive) when paired

### Protocols Added
- `VoiceEngineProtocol` — abstracts VoiceEngine for DI/testing
- `GatewayConnecting` — abstracts GatewayConnection for DI/testing
- `ResponseSpeaking` — abstracts ResponseSpeaker for DI/testing
- GatewayConnection and ResponseSpeaker conform to their protocols via extensions

### Tests
- 15 VoiceChatCoordinator tests covering: session lifecycle, utterance→gateway flow, chat.event→speaker flow, interrupts, session keys
- 10 PairingViewModel tests covering: initial state, connect, paired state, unpair, connection status

## Files Changed
- **New:** `VoiceChatCoordinator.swift`, `VoiceChatCoordinatorTests.swift`
- **New:** `PairingViewModel.swift`, `PairingViewModelTests.swift`
- **New:** `PairingSectionView.swift`
- **Modified:** `SettingsView.swift` (added pairing section)
- **Modified:** `TestDoubles.swift` (added mock doubles for new protocols)
- **Modified:** `project.pbxproj` (registered all new files)
