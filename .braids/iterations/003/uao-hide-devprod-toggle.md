# Hide Dev/Prod Config Toggle on Real Devices (zaap-uao)

## Changes

**File:** `Zaap/Zaap/SettingsView.swift`

1. Moved the "Use development config?" toggle inside the existing `#if targetEnvironment(simulator)` block — only renders in simulator now.
2. Wrapped the footer text (dev vs prod URL) in `#if targetEnvironment(simulator)` / `#else` so real devices always show "Production: REDACTED_HOSTNAME".

## Notes

- `useDevConfig` in SettingsManager already defaults to `false` on real devices.
- Pre-existing build error in VoiceEngineAdapters.swift (unrelated) prevents full build verification.
