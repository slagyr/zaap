# zaap-3bz: Voice Transcripts Cut Off Fix

## Problem
After `emitUtteranceIfValid()` called `restartRecognition()`, the new speech recognition task started with a fresh transcript, but `lastEmittedLength` retained the old value. When the new task returned shorter text (e.g. 18 chars) but `lastEmittedLength` was 24 from the old transcript, `String.dropFirst(24)` produced an empty string — so the utterance was silently dropped.

## Root Cause
In `emitUtteranceIfValid()`:
```swift
lastEmittedLength = full.count  // e.g. 24
restartRecognition()            // new task starts fresh at 0
```

The new recognition task's transcript starts from scratch, but `lastEmittedLength` still reflected the OLD transcript's total length.

## Fix
Changed `lastEmittedLength = full.count` to `lastEmittedLength = 0` in `emitUtteranceIfValid()`, since `restartRecognition()` creates a brand new recognition task with an independent transcript space.

## Tests
- Added `testSecondUtteranceOnFreshTaskEmitsFullText` — directly reproduces the bug scenario
- Updated `testSecondUtteranceEmitsOnlyNewPortion` to model correct fresh-task behavior
- All 34 VoiceEngine tests pass
