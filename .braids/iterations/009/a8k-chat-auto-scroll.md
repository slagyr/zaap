# zaap-a8k: Chat transcript does not auto-scroll

## Problem
New messages appeared below the visible area. The `.onChange` handler only triggered on `conversationLog.count` changes, missing streaming response text and partial transcript updates.

## Fix
In `VoiceChatView.swift`:
1. Added invisible bottom anchor (`Color.clear` with id `"bottom-anchor"`) at end of LazyVStack
2. Added `.onChange` handlers for `partialTranscript` and `responseText` alongside `conversationLog.count`
3. All scroll to bottom anchor with animation

## Acceptance Criteria
- [x] ScrollViewReader wrapping LazyVStack (already existed)
- [x] onChange triggers scroll on new entries, partial transcript, and streaming response
- [x] Response bubbles visible without manual scrolling
- [x] Smooth animated scroll via withAnimation
