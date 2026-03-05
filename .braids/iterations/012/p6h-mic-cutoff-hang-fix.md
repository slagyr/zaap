# zaap-p6h: Mic cuts off mid-sentence and hangs

## Problem

Mid-conversation, STT captures a partial sentence then stops. The utterance is never sent to the agent and the UI hangs waiting for input that never completes. This is distinct from the transcript reset bug (zaap-x9d) — here the STT stops entirely rather than resetting.

## Root Cause

Two issues in `VoiceEngine.swift`:

1. **Error handler did not finalize transcript:** When the recognition task errored out after partials were received, the engine reported the error via `onError` but did NOT finalize the partial transcript or restart recognition. The engine relied entirely on the silence timer as a fallback, which can fail in edge cases (run loop mode changes, app backgrounding, timer scheduling delays). This left the engine with `isListening = true` but a dead recognition task — a hang.

2. **Restarted task missing `hasReceivedPartial` update:** The recognition task callback in `restartRecognition()` did not update `hasReceivedPartial` when results arrived. This meant errors after partials on restarted tasks were wrongly suppressed as "cold-start" errors, preventing finalization of the transcript.

## Fix

### VoiceEngine.swift

- **Added `handleRecognitionError(_:)`** — Centralized error handler for both initial and restarted recognition tasks. When an error occurs after partials were received, it actively finalizes any pending transcript and restarts recognition to recover from the dead task.

- **Added `finalizeTranscriptOnError()`** — Cancels silence/debounce timers, builds the full transcript (pending + current), emits via `onUtteranceComplete` if valid (≥ 3 chars), clears state, and restarts recognition. Safe to call even when transcript is empty (no-op in that case).

- **Added `hasReceivedPartial` update to restart handler** — The recognition task callback in `restartRecognition()` now updates `hasReceivedPartial = true` and cancels the watchdog when the first result arrives, matching the behavior of the initial task handler.

- **Deduplicated error handling** — Both the `startListening()` and `restartRecognition()` task callbacks now delegate to the same `handleRecognitionError()` method.

### VoiceEngineTests.swift — 4 new tests

1. `testRecognitionErrorAfterPartialsFinalizesTranscript` — Verifies partial transcript is emitted when recognition errors mid-speech
2. `testRecognitionErrorAfterPartialsRestartsRecognition` — Verifies a new recognition task is created after error recovery
3. `testRecognitionErrorWithPendingDebounceFinalizesAll` — Verifies pending transcript from isFinal debounce + current text are both finalized on error
4. `testRecognitionErrorWithShortTranscriptDoesNotEmit` — Verifies short transcripts aren't emitted on error, but recognition still restarts

## Test Results

- VoiceEngineTests: 66 tests, 0 failures
- VoiceChatCoordinatorTests: 115 tests, 0 failures
