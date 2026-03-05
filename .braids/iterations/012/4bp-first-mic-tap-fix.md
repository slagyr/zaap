# zaap-4bp: First mic tap still does nothing after build 42

## Root Cause

Two bugs in `VoiceChatCoordinator.startSession()`:

1. **No visual feedback when gateway is still connecting.** When the user taps mic before the gateway handshake completes (`.connecting` or `.challenged` state), `startSession` entered the `else` branch which called `gateway.connect()` (a no-op since already connecting) but **never called `viewModel.tapMic()`**. The user saw zero UI change — "does nothing."

2. **Double-toggle on gateway connect.** `gatewayDidConnect()` unconditionally called `viewModel.tapMic()`, which is a toggle. If the session was already in `.listening` state (from the direct path when gateway was already connected), `tapMic()` would toggle it back to `.idle`, breaking the session.

### Why the second tap worked

After the "nothing" first tap, the session was technically active (`isSessionActive = true, isConversationModeOn = true`) but the viewModel was stuck in `.idle`. The second tap called `toggleConversationMode()` which toggled conversation mode OFF, then a third tap toggled it ON — this path calls `voiceEngine.startListening()` directly without depending on gateway state, so it worked.

### Why zaap-9bu didn't fix it

The previous fix (zaap-9bu) only changed `ThinkingSoundPlayer` sound characteristics (chord → sonar ping). It never touched the mic activation path.

## Changes Made

### VoiceChatCoordinator.swift

- **`startSession()`:** Always call `viewModel.tapMic()` for immediate visual feedback, regardless of gateway connection state. Only start voice engine if gateway is already `.connected`; otherwise wait for `gatewayDidConnect`.
- **`gatewayDidConnect()`:** Replace unconditional `viewModel.tapMic()` toggle with idempotent state checks: only call `voiceEngine.startListening()` if not already listening, only call `viewModel.tapMic()` if viewModel is in `.idle` state.

### VoiceChatCoordinatorTests.swift — 6 new tests

- `testStartSessionProvidesImmediateFeedbackWhenGatewayConnecting` — verifies UI transitions to `.listening` when gateway is `.connecting`
- `testStartSessionWhenGatewayConnectingDoesNotDoubleToggleOnConnect` — verifies gateway connect doesn't toggle state back to idle
- `testStartSessionWhenGatewayAlreadyConnectedStartsImmediately` — verifies direct path when gateway is ready
- `testStartSessionWhenGatewayDisconnectedStartsAfterConnect` — verifies deferred voice engine start
- `testGatewayDidConnectDoesNotDoubleToggleViewModelFromListening` — verifies reconnect safety
- `testGatewayReconnectStartsMicWhenItWasStopped` — verifies mic restart on reconnect when stopped

Updated `testGatewayReconnectRestartsMicWhenConversationModeOn` to verify engine *stays* listening (no redundant restart) rather than asserting `startListeningCalled` flag.

## Verification

- `xcodebuild test -scheme Zaap`: All 48 test suites passed, 0 failures
- All 6 new tests pass
- All existing coordinator tests pass (including updated reconnect test)
