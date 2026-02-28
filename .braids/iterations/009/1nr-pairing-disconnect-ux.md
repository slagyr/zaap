# zaap-1nr: Pairing flow no longer shows red "Disconnected" before approval

## Problem
When an unpaired device connects to the gateway, the NOT_PAIRED response triggers both `gatewayDidFailWithError` and `gatewayDidDisconnect`. The disconnect callback fired first, showing a red "Disconnected from gateway" error before the error handler could set "Awaiting approval".

## Changes

### PairingView.swift
- Added DI to VoicePairingViewModel (optional pairingManager + gateway params)
- Changed gateway type from GatewayConnection to GatewayConnecting protocol
- Fixed gatewayDidDisconnect(): only shows red error when disconnecting from .paired state (not during .connecting)
- Made status internal for testability

### PairingViewModelTests.swift
Added 6 tests verifying:
- Disconnect during connecting does NOT show red error
- NOT_PAIRED error correctly transitions to .awaitingApproval
- Genuine disconnects after pairing DO show red error
- Auth failures show .failed state
