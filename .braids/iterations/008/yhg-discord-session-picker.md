# zaap-yhg: Session picker — Discord sessions only, require selection

## Changes

### SessionPickerViewModel.swift
- Added `channelType: String?` to `GatewaySession` model
- `loadSessions()` now filters results to `channelType == "discord"` only
- Auto-selects first (most recent) Discord session; preserves existing valid selection
- Added `isSessionSelected` computed property for mic button gating

### SessionPickerView.swift
- Removed "New conversation" option from picker
- Shows "No Discord sessions available" when session list is empty

### GatewayConnection.swift
- Parses `channelType` from gateway `sessions.list` response

### VoiceChatView.swift
- Mic button disabled when no session is selected (`.disabled(!sessionPicker.isSessionSelected)`)

## Tests Added (8 new)
- `testLoadSessionsFiltersToDiscordOnly` — non-discord sessions excluded
- `testLoadSessionsFiltersOutNilChannelType` — nil channelType excluded
- `testLoadSessionsAutoSelectsFirstSession` — defaults to most recent
- `testLoadSessionsDoesNotOverrideExistingSelection` — preserves valid selection
- `testLoadSessionsClearsSelectionIfSelectedSessionNoLongerExists` — resets stale selection
- `testLoadSessionsNoDiscordSessionsClearsSelection` — clears when no discord sessions
- `testIsSessionSelectedReturnsFalseWhenNoSelection`
- `testIsSessionSelectedReturnsTrueWhenSelected`
