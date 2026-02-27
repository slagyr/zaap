# Fix Mic Button (zaap-eky)

## Problem
Mic button was permanently disabled because SessionPickerViewModel filtered sessions to channelType == "discord", but the gateway never sends a channelType field — so all sessions were dropped.

## Changes

### GatewayConnection.swift
- Added deriveChannelType(from:) static method that parses session key format (agent:main:<channel>:<id>)
- handleSessionListResponse now falls back to derived channelType when the field is missing
- Explicit channelType from gateway is preserved if present

### SessionPickerViewModel.swift
- Removed Discord-only filter — all sessions are now shown
- Auto-select priority: keep existing selection → prefer agent:main:main → fallback to first
- Fixed duplicate selectedSessionTitle computed property

### Tests
- Updated SessionPickerViewModelTests with all-sessions and agent:main:main auto-selection tests
- Added GatewayConnectionTests for channelType derivation (3 integration + 3 unit)
- All 403 tests pass, 0 failures
