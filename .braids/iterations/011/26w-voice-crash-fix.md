# zaap-26w: App crash on real device during voice chat

## Summary
Fixed multiple crash-prone patterns in the voice chat pipeline that could cause crashes on real devices.

## Changes

### 1. Force Unwrap Elimination (Crash Fix)
Removed all force unwraps from production code per iteration guardrail:
- **NodePairingManager**: `payload.data(using: .utf8)!` → guard let with error throwing (3 instances)
- **PairingViewModel**: `URL(string:)!` → guard let with error state
- **VoiceEngineAdapters**: `SFSpeechRecognizer()!` → optional with graceful degradation
- **RequestLog**, **DashboardView**, **HealthDataSeeder**: safe fallbacks

### 2. Thread-Safe WebSocket Access (Crash Fix)
Added NSLock to GatewayConnection to prevent concurrent access to webSocket property across tasks.

### 3. Software Echo Suppression
Stop mic during TTS playback; track spoken text to filter STT echo; restart mic after TTS completes.

## Test Results
191 tests passed, 0 failures.
