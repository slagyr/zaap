import XCTest
import CryptoKit
@testable import Zaap

final class NodePairingManagerTests: XCTestCase {

    var mockKeychain: MockKeychainAccess!
    var manager: NodePairingManager!

    override func setUp() {
        super.setUp()
        mockKeychain = MockKeychainAccess()
        manager = NodePairingManager(keychain: mockKeychain)
    }

    // MARK: - Identity Generation

    func testGenerateIdentityCreatesEd25519Keypair() throws {
        let identity = try manager.generateIdentity()

        XCTAssertFalse(identity.nodeId.isEmpty)
        XCTAssertFalse(identity.publicKeyBase64.isEmpty)
    }

    func testGenerateIdentityNodeIdIsSha256OfPublicKey() throws {
        let identity = try manager.generateIdentity()

        // Decode the base64url public key, hash it, and verify nodeId matches
        let base64 = identity.publicKeyBase64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)
        let publicKeyData = Data(base64Encoded: padded)!
        let hash = SHA256.hash(data: publicKeyData)
        let expectedNodeId = hash.map { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(identity.nodeId, expectedNodeId)
    }

    func testGenerateIdentityStoresPrivateKeyInKeychain() throws {
        _ = try manager.generateIdentity()

        XCTAssertTrue(mockKeychain.savedKeys.keys.contains("co.airworthy.zaap.node.privateKey"))
    }

    func testGenerateIdentityStoresPublicKeyInKeychain() throws {
        _ = try manager.generateIdentity()

        XCTAssertTrue(mockKeychain.savedKeys.keys.contains("co.airworthy.zaap.node.publicKey"))
    }

    func testGenerateIdentityStoresBothKeysInKeychain() throws {
        _ = try manager.generateIdentity()

        XCTAssertEqual(mockKeychain.savedKeys.count, 2)
    }

    func testGenerateIdentityIsConsistentWhenCalledTwice() throws {
        let identity1 = try manager.generateIdentity()
        let identity2 = try manager.generateIdentity()

        // Second call should generate new keys (not reuse)
        // But if keys already exist in keychain, it should return them
        XCTAssertEqual(identity1.nodeId, identity2.nodeId)
        XCTAssertEqual(identity1.publicKeyBase64, identity2.publicKeyBase64)
    }

    func testGenerateIdentityReturnsExistingKeysFromKeychain() throws {
        // Generate once
        let identity1 = try manager.generateIdentity()

        // Create a new manager with the same keychain (simulating app restart)
        let manager2 = NodePairingManager(keychain: mockKeychain)
        let identity2 = try manager2.generateIdentity()

        XCTAssertEqual(identity1.nodeId, identity2.nodeId)
    }

    // MARK: - Challenge Signing

    private let testDeviceId = "device-1"
    private let testClientId = "client-1"
    private let testClientMode = "node"
    private let testRole = "peer"
    private let testScopes = ["voice", "hooks"]
    private let testToken = "tok-123"

    private func signChallenge(nonce: String) throws -> ChallengeSignature {
        try manager.signChallenge(
            nonce: nonce,
            deviceId: testDeviceId,
            clientId: testClientId,
            clientMode: testClientMode,
            role: testRole,
            scopes: testScopes,
            token: testToken
        )
    }

    func testSignChallengeProducesValidSignature() throws {
        _ = try manager.generateIdentity()
        let nonce = "test-nonce-12345"

        let result = try signChallenge(nonce: nonce)

        XCTAssertFalse(result.signature.isEmpty)
        XCTAssertGreaterThan(result.signedAt, 0)
    }

    func testSignChallengeFailsWithoutIdentity() {
        XCTAssertThrowsError(try signChallenge(nonce: "test")) { error in
            XCTAssertEqual(error as? NodePairingError, .noIdentity)
        }
    }

    func testSignChallengeSignatureIsVerifiable() throws {
        let identity = try manager.generateIdentity()
        let nonce = "verify-me-nonce"

        let result = try signChallenge(nonce: nonce)

        // Verify signature using the public key
        // Decode base64url public key
        let pubBase64 = identity.publicKeyBase64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pubPadded = pubBase64 + String(repeating: "=", count: (4 - pubBase64.count % 4) % 4)
        let publicKeyData = Data(base64Encoded: pubPadded)!
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        // Decode base64url signature
        let sigBase64 = result.signature
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let sigPadded = sigBase64 + String(repeating: "=", count: (4 - sigBase64.count % 4) % 4)
        let signatureData = Data(base64Encoded: sigPadded)!
        let scopesStr = testScopes.joined(separator: ",")
        // v3 payload includes platform and deviceFamily
        let payload = ["v3", testDeviceId, testClientId, testClientMode, testRole, scopesStr,
                       String(result.signedAt), testToken, nonce, "ios", "mobile"].joined(separator: "|")
        let message = payload.data(using: .utf8)!

        XCTAssertTrue(publicKey.isValidSignature(signatureData, for: message))
    }

    func testSignChallengeSignedAtIsCurrentTimestamp() throws {
        _ = try manager.generateIdentity()
        let beforeMs = Int(Date().timeIntervalSince1970 * 1000)
        let result = try signChallenge(nonce: "time-test")
        let afterMs = Int(Date().timeIntervalSince1970 * 1000)

        XCTAssertGreaterThanOrEqual(result.signedAt, beforeMs)
        XCTAssertLessThanOrEqual(result.signedAt, afterMs)
    }

    // MARK: - Token Storage

    func testStoreTokenSavesToKeychain() throws {
        try manager.storeToken("my-secret-token")

        XCTAssertEqual(mockKeychain.savedKeys["co.airworthy.zaap.node.token"], "my-secret-token".data(using: .utf8))
    }

    func testLoadTokenRetrievesFromKeychain() throws {
        try manager.storeToken("my-secret-token")

        let token = manager.loadToken()
        XCTAssertEqual(token, "my-secret-token")
    }

    func testLoadTokenReturnsNilWhenNoToken() {
        let token = manager.loadToken()
        XCTAssertNil(token)
    }

    // MARK: - Gateway URL Storage

    func testStoreGatewayURLSavesToKeychain() throws {
        let url = URL(string: "ws://192.168.1.100:18789")!
        try manager.storeGatewayURL(url)

        let stored = mockKeychain.savedKeys["co.airworthy.zaap.node.gatewayURL"]
        XCTAssertEqual(stored, url.absoluteString.data(using: .utf8))
    }

    func testLoadGatewayURLRetrievesFromKeychain() throws {
        let url = URL(string: "ws://192.168.1.100:18789")!
        try manager.storeGatewayURL(url)

        let loaded = manager.loadGatewayURL()
        XCTAssertEqual(loaded, url)
    }

    func testLoadGatewayURLReturnsNilWhenNotStored() {
        XCTAssertNil(manager.loadGatewayURL())
    }

    // MARK: - Pairing State

    func testIsPairedReturnsFalseInitially() {
        XCTAssertFalse(manager.isPaired)
    }

    func testIsPairedReturnsTrueWhenTokenExists() throws {
        try manager.storeToken("some-token")
        XCTAssertTrue(manager.isPaired)
    }

    // MARK: - Clear Pairing

    func testClearPairingRemovesAllKeys() throws {
        _ = try manager.generateIdentity()
        try manager.storeToken("token")
        try manager.storeGatewayURL(URL(string: "ws://localhost:18789")!)

        manager.clearPairing()

        XCTAssertTrue(mockKeychain.savedKeys.isEmpty)
        XCTAssertFalse(manager.isPaired)
    }

    // MARK: - Pairing Request Message

    func testBuildPairRequestMessage() throws {
        let identity = try manager.generateIdentity()

        let message = manager.buildPairRequestMessage()

        XCTAssertNotNil(message)
        let msg = message!
        XCTAssertEqual(msg["type"] as? String, "request")
        XCTAssertEqual(msg["method"] as? String, "node.pair.request")
        XCTAssertNotNil(msg["id"] as? String)

        let params = msg["params"] as? [String: Any]
        XCTAssertNotNil(params)
        XCTAssertEqual(params?["nodeId"] as? String, identity.nodeId)
        XCTAssertEqual(params?["displayName"] as? String, "Zaap (iPhone)")
        XCTAssertEqual(params?["platform"] as? String, "iOS")
        XCTAssertEqual(params?["publicKey"] as? String, identity.publicKeyBase64)

        let caps = params?["caps"] as? [String]
        XCTAssertEqual(caps, ["voice"])
    }

    func testBuildPairRequestMessageReturnsNilWithoutIdentity() {
        let message = manager.buildPairRequestMessage()
        XCTAssertNil(message)
    }
}

// MARK: - SimulatorKeychain Tests

final class SimulatorKeychainTests: XCTestCase {

    var keychain: SimulatorKeychain!
    let testSuite = "co.airworthy.zaap.test"

    override func setUp() {
        super.setUp()
        // Clean slate for each test
        UserDefaults.standard.removePersistentDomain(forName: testSuite)
        keychain = SimulatorKeychain(suiteName: testSuite)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: testSuite)
        super.tearDown()
    }

    func testSaveAndLoadReturnsStoredData() throws {
        let data = "hello".data(using: .utf8)!
        try keychain.save(key: "testKey", data: data)

        let loaded = keychain.load(key: "testKey")
        XCTAssertEqual(loaded, data)
    }

    func testLoadReturnsNilForMissingKey() {
        XCTAssertNil(keychain.load(key: "nonexistent"))
    }

    func testDeleteRemovesStoredData() throws {
        let data = "hello".data(using: .utf8)!
        try keychain.save(key: "testKey", data: data)

        keychain.delete(key: "testKey")

        XCTAssertNil(keychain.load(key: "testKey"))
    }

    func testSaveOverwritesExistingData() throws {
        try keychain.save(key: "testKey", data: "first".data(using: .utf8)!)
        try keychain.save(key: "testKey", data: "second".data(using: .utf8)!)

        let loaded = keychain.load(key: "testKey")
        XCTAssertEqual(loaded, "second".data(using: .utf8)!)
    }

    func testDataPersistsAcrossInstances() throws {
        let data = "persist".data(using: .utf8)!
        try keychain.save(key: "testKey", data: data)

        let keychain2 = SimulatorKeychain(suiteName: testSuite)
        XCTAssertEqual(keychain2.load(key: "testKey"), data)
    }

    func testNodePairingManagerWorksWithSimulatorKeychain() throws {
        let manager = NodePairingManager(keychain: keychain)
        let identity1 = try manager.generateIdentity()

        // Simulate app restart with same UserDefaults-backed keychain
        let keychain2 = SimulatorKeychain(suiteName: testSuite)
        let manager2 = NodePairingManager(keychain: keychain2)
        let identity2 = try manager2.generateIdentity()

        XCTAssertEqual(identity1.nodeId, identity2.nodeId)
        XCTAssertEqual(identity1.publicKeyBase64, identity2.publicKeyBase64)
    }
}
