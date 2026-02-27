# zaap-k20: Remove navigation titles from all tabs

## Summary
Removed redundant navigation titles from all three tabs (Dashboard, Voice, Settings) and hid the navigation bar entirely using `.toolbar(.hidden, for: .navigationBar)`.

## Changes
- **VoiceChatView.swift**: Replaced `.navigationTitle("Voice")` with `.toolbar(.hidden, for: .navigationBar)`
- **SettingsView.swift**: Replaced `.navigationTitle("Settings")` with `.toolbar(.hidden, for: .navigationBar)`
- **DashboardView.swift**: Added `.toolbar(.hidden, for: .navigationBar)` (had no title but still showed empty nav bar space)

## Notes
- Implementation was already committed in `132be25` by a prior worker but the bead was never closed
- All tests pass with 0 failures
