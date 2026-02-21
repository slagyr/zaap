# NodePairingManager — zaap-aqb

## Summary

Implemented `NodePairingManager` with full TDD coverage (19 tests, all passing).

## What Was Built

### NodePairingManager.swift
- **Ed25519 keypair generation** via CryptoKit `Curve25519.Signing`
- **NodeId** = SHA-256 hex digest of the public key raw representation
- **Keychain storage** via `KeychainAccessing` protocol (injectable for testing)
- **Challenge signing** — signs `"<nonce>:<signedAt>"` with Ed25519 private key, returns base64 signature + timestamp
- **Token storage** — store/load pairing token from Keychain
- **Gateway URL storage** — store/load gateway URL from Keychain
- **Pairing state** — `isPaired` computed from token presence
- **Clear pairing** — removes all keys from Keychain
- **Build pair request message** — constructs `node.pair.request` JSON-RPC message with nodeId, displayName ("Zaap (iPhone)"), platform ("iOS"), publicKey, caps (["voice"])

### KeychainAccessing Protocol
- Defined in NodePairingManager.swift
- `save(key:data:)`, `load(key:)`, `delete(key:)`
- Real Keychain implementation deferred to integration (GatewayConnection bead)

### MockKeychainAccess (TestDoubles.swift)
- In-memory dictionary-based mock for unit tests

### Test Coverage (19 tests)
- Identity generation: keypair creation, SHA-256 nodeId, Keychain persistence, idempotent retrieval
- Challenge signing: valid signature, verifiable with public key, current timestamp, error without identity
- Token/URL storage: save, load, nil when absent
- Pairing state: isPaired true/false
- Clear pairing: removes all keys
- Pair request message: correct JSON-RPC structure, nil without identity

## Files Changed
- `Zaap/Zaap/NodePairingManager.swift` (new)
- `Zaap/ZaapTests/NodePairingManagerTests.swift` (new)
- `Zaap/ZaapTests/TestDoubles.swift` (added MockKeychainAccess)
- `Zaap/Zaap.xcodeproj/project.pbxproj` (added file references)

## Notes for Downstream (zaap-89d: GatewayConnection)
- A real `KeychainAccess` struct implementing `KeychainAccessing` with `SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete` will be needed for production
- `buildPairRequestMessage()` returns the JSON-RPC dict for `node.pair.request`
- `signChallenge(nonce:)` is ready for the `connect.challenge` → `connect` handshake flow
