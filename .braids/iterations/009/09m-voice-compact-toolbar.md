# zaap-09m: Voice tab UI — compact single-row toolbar

## Changes

### VoiceChatView.swift
- Replaced the bottom section (SessionPickerView + Divider + VStack with statusView + micButton) with a **single HStack toolbar row**: `[session picker menu] — [status dot] — [mic button 44pt]`
- Added `compactSessionPicker`: a Menu-based session picker that shows session title inline
- Added `statusDot`: minimal status indicator (colored dot for listening/speaking, ProgressView for processing, EmptyView for idle)
- Reduced mic button from 72pt to 44pt
- Moved "Tap the mic to start" hint into a `.overlay` on the ScrollView (floats in transcript area, adds zero height to toolbar)
- The transcript ScrollView now fills all remaining vertical space above the single toolbar row

### SessionPickerViewModel.swift
- Added `selectedSessionTitle` computed property returning the selected session's title or "New conversation"

## Verification
The bottom section is now ONE HStack row only. No VStack wrapping mic button below the ScrollView. The hint text is an overlay on the ScrollView, not a toolbar child.
