# GatewayConnection — zaap-89d

## Summary

Implemented `GatewayConnection`, a WebSocket client that connects Zaap to the OpenClaw gateway as a paired node. Handles the full connect handshake (challenge-response with Ed25519 device signature), routes incoming messages by type, and supports exponential backoff reconnection.

## Files Added

- `Zaap/Zaap/GatewayConnection.swift` — Main implementation
- `Zaap/ZaapTests/GatewayConnectionTests.swift` — 24 tests, all passing

## Architecture

### Protocols (for testability)
- `WebSocketTaskProtocol` — abstracts `URLSessionWebSocketTask`
- `WebSocketFactory` — creates WebSocket tasks
- `NetworkPathMonitoring` — abstracts `NWPathMonitor`
- `GatewayConnectionDelegate` — receives connect/disconnect/event/error callbacks

### Connection Flow
1. `connect(to:)` → creates WebSocket, sets state to `.connecting`
2. Receives `connect.challenge` with nonce → signs with `NodePairingManager`, sends connect response with device identity, token, and capabilities
3. Receives `hello-ok` → sets state to `.connected`, notifies delegate
4. Receive loop routes messages: `node.*` and `chat.*` events forwarded to delegate

### Reconnection
- Exponential backoff: 1s → 2s → 4s → 8s → 16s → 30s (capped)
- Resets on successful connection
- Network monitor triggers immediate reconnect when path becomes available
- Intentional `disconnect()` suppresses reconnection

### Sending
- `sendEvent(_:payload:)` — sends `node.event` JSON-RPC message
- `sendVoiceTranscript(_:sessionKey:)` — convenience for `voice.transcript` events

## Test Coverage

24 tests covering:
- Initial state, connect/disconnect lifecycle
- Challenge-response handshake (including error cases)
- Hello-ok state transition and delegate notification
- Message routing (node.invoke.request, chat.event)
- Backoff delay calculation (all intervals + cap)
- Network monitor initialization
- Send-when-disconnected error handling
- Invalid JSON error reporting
