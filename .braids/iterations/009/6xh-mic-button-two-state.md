# zaap-6xh: Mic button blue/red two-state only

Simplified `micButtonColor` in `VoiceChatView.swift`:
- Blue when idle, Red for all active states (listening/processing/speaking)
- Removed orange and green from mic button
- statusDot still distinguishes states visually (per AC)
