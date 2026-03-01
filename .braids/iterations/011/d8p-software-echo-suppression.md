# zaap-d8p: Software Echo Suppression

## Problem
Hardware AEC via `.voiceChat` audio session mode is insufficient on real iPhone devices. TTS output gets picked up by the microphone and transcribed by STT, creating echo loops where the assistant's own spoken words are sent back as user input.

## Solution: Two-Layer Echo Suppression

### Layer 1: Mic Muting During TTS
- **Stop listening** when the speaker starts speaking (`.speaking` state)
- **Resume listening** after the speaker finishes (`.idle` state), with the existing delayed restart
- This prevents the microphone from capturing TTS audio entirely

### Layer 2: Software Echo Filtering (Safety Net)
- **Track recently spoken text** — every text sent to the speaker is recorded in a ring buffer (`recentSpokenTexts`, max 10 entries)
- **Filter STT transcripts** — before sending an utterance to the gateway, check if it matches any recently spoken text
- **Fuzzy matching** — text is normalized (lowercased, punctuation stripped) and compared with substring containment in both directions
- If a match is found, the utterance is discarded with a log message

### Changes
- `VoiceChatCoordinator.swift`:
  - `speaker.onStateChange` now stops voice engine when state is `.speaking`
  - Added `trackSpokenText(_:)` — public method to record TTS text
  - Added `isEcho(_:)` — checks transcript against recent spoken text
  - Added `normalizeForEchoComparison(_:)` — strips punctuation, lowercases
  - `handleUtteranceComplete` filters echo before sending to gateway
  - `handleChatEvent` and legacy token path track spoken text

### Tests (55 passing)
- `testMicStopsWhenSpeakerStartsSpeaking` — verifies mic stops during TTS
- `testUtteranceMatchingRecentSpokenTextIsFiltered` — echo is discarded
- `testUtteranceNotMatchingSpokenTextIsNotFiltered` — real user speech passes through
- `testSpokenTextTrackedFromSpeakerBufferToken` — gateway responses are tracked for echo filtering
- All existing conversation mode, session key, and lifecycle tests still pass

### Note
Full test suite has a pre-existing simulator crash (`signal kill before establishing connection`) that also occurs on HEAD without these changes. All coordinator-specific tests pass (55/55).
