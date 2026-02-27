# Fix Persistent Transcript Accumulation (zaap-0wt)

## Problem
SFSpeechRecognizer returns cumulative bestTranscriptionString for the lifetime of a recognition request. After emitting an utterance, late callbacks would re-populate currentTranscript with the full accumulated text.

## Solution: Utterance Offset Tracking
Added lastEmittedLength to track how much of the cumulative transcript has been emitted. emitUtteranceIfValid() now extracts only the NEW portion via dropFirst(lastEmittedLength). Safe even with late callbacks from cancelled tasks.

## Changes
- **VoiceEngine.swift**: Added lastEmittedLength, offset tracking in emitUtteranceIfValid(), reset in stopListening() and startListening()
- **VoiceEngineTests.swift**: 4 new tests + 1 updated test

## Tests
- testStopListeningClearsCurrentTranscript
- testSecondUtteranceEmitsOnlyNewPortion
- testStartListeningResetsEmittedOffset
- testLateCallbackAfterEmitDoesNotReEmitOldText
