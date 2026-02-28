# zaap-g3w: Session picker — fix RPC population, filter to discord + main only

## Changes

### SessionPickerViewModel.swift
- Added filtering in `loadSessions()`: only keeps sessions where `key == "agent:main:main"` or `key.contains(":discord:")`
- Added logging: prints number of sessions returned, each session's key/title/channelType, and count after filtering
- Error path logs the failure reason
- Main fallback (`agent:main:main`) always present, even on RPC failure

### SessionPickerViewModelTests.swift
- Updated tests to verify filtering behavior (whatsapp, cron, telegram, sub-agent sessions excluded)
- Tests confirm Main fallback always present
- Tests confirm auto-select logic with filtered results
- All 21 tests pass

## Files Modified
- `Zaap/Zaap/SessionPickerViewModel.swift`
- `Zaap/ZaapTests/SessionPickerViewModelTests.swift`
