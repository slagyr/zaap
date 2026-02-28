# zaap-8kt: Stable Device ID on Simulator

## Problem
Simulator Keychain is wiped on every reinstall, generating a new Ed25519 keypair and device ID each time.

## Solution
- Added `SimulatorKeychain` in `VoiceEngineAdapters.swift` — `KeychainAccessing` backed by `UserDefaults`
- Added convenience `init()` on `NodePairingManager` with `#if targetEnvironment(simulator)`
- Updated all call sites to use the no-arg init

## Tests
6 new tests in `SimulatorKeychainTests` — all passing.
