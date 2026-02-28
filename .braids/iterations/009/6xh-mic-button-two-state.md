# zaap-6xh: Mic button blue/red two-state only

## Change

Simplified `micButtonColor` in `VoiceChatView.swift` to return exactly two colors:
- **Blue** when idle (tap to start)
- **Red** when listening, processing, or speaking (tap to stop)

Removed the orange (processing) and green (speaking) states from the mic button.

## What Was NOT Changed

- `statusDot` still uses distinct indicators per state — per AC, status indicators may appear elsewhere
- `micIconName` still varies per state — icon differentiation is fine, only color was the issue

## Verification

```
grep micButtonColor VoiceChatView.swift
# Returns exactly: .blue and .red (no other colors)
```
