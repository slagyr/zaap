# Echo Cancellation Fix (zaap-jgm)

## Problem
TTS speaker output was fed back into the microphone, causing the assistant to hear and respond to its own voice in a feedback loop.

## Solution
**Mic muting during TTS playback** via a state change callback:

1. `ResponseSpeaker.onStateChange` — callback fired on `.idle` ↔ `.speaking` transitions
2. `VoiceChatCoordinator` — wires callback to stop/start voice engine when speaker state changes
3. Guard on `isActive` prevents mic resume after session stopped

## Tests (6 new)
- Coordinator: mic stops on speak, resumes on idle, no resume after session stop
- ResponseSpeaker: callback on speak, callback on finish, no duplicate for same state

## Files Changed
- ResponseSpeaker.swift, VoiceChatCoordinator.swift, TestDoubles.swift, test files
