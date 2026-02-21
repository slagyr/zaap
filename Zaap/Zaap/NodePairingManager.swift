import Foundation
import CryptoKit

/// Errors from NodePairingManager operations.
enum NodePairingError: Error, Equatable {
    case noIdentity
    case keychainError(String)
}

/// Result of identity generation.
struct NodeIdentity: Equatable {
    let nodeId: String
    let publicKeyBase64: String
}

/// Result of challenge signing.
struct ChallengeSignature {
    let signature: String
    let signedAt: Int
}

/// Protocol for Keychain access, enabling test doubles.
protocol KeychainAccessing {
    func save(key: String, data: Data) throws
    func load(key: String) -> Data?
    func delete(key: String)
}

/// Manages node identity (Ed25519 keypair), Keychain storage, and pairing state.
class NodePairingManager {

    private let keychain: KeychainAccessing
    private var cachedPrivateKey: Curve25519.Signing.PrivateKey?
    private var cachedIdentity: NodeIdentity?

    private static let privateKeyTag = "co.airworthy.zaap.node.privateKey"
    private static let publicKeyTag = "co.airworthy.zaap.node.publicKey"
    private static let tokenTag = "co.airworthy.zaap.node.token"
    private static let gatewayURLTag = "co.airworthy.zaap.node.gatewayURL"

    init(keychain: KeychainAccessing) {
        self.keychain = keychain
    }

    /// Generate or retrieve an Ed25519 identity. NodeId = sha256(publicKey).
    func generateIdentity() throws -> NodeIdentity {
        // Check if we already have keys in keychain
        if let existingPrivateKeyData = keychain.load(key: Self.privateKeyTag),
           let existingPublicKeyData = keychain.load(key: Self.publicKeyTag) {
            let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: existingPrivateKeyData)
            cachedPrivateKey = privateKey
            let identity = NodeIdentity(
                nodeId: Self.sha256Hex(existingPublicKeyData),
                publicKeyBase64: existingPublicKeyData.base64EncodedString()
            )
            cachedIdentity = identity
            return identity
        }

        // Generate new keypair
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyData = privateKey.publicKey.rawRepresentation

        try keychain.save(key: Self.privateKeyTag, data: privateKey.rawRepresentation)
        try keychain.save(key: Self.publicKeyTag, data: publicKeyData)

        cachedPrivateKey = privateKey
        let identity = NodeIdentity(
            nodeId: Self.sha256Hex(publicKeyData),
            publicKeyBase64: publicKeyData.base64EncodedString()
        )
        cachedIdentity = identity
        return identity
    }

    /// Sign a nonce for the connect handshake.
    func signChallenge(nonce: String) throws -> ChallengeSignature {
        guard let privateKey = cachedPrivateKey else {
            throw NodePairingError.noIdentity
        }

        let signedAt = Int(Date().timeIntervalSince1970)
        let message = "\(nonce):\(signedAt)".data(using: .utf8)!
        let signature = try privateKey.signature(for: message)

        return ChallengeSignature(
            signature: signature.base64EncodedString(),
            signedAt: signedAt
        )
    }

    /// Store the pairing token in Keychain.
    func storeToken(_ token: String) throws {
        try keychain.save(key: Self.tokenTag, data: token.data(using: .utf8)!)
    }

    /// Load the pairing token from Keychain.
    func loadToken() -> String? {
        guard let data = keychain.load(key: Self.tokenTag) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Store the gateway URL in Keychain.
    func storeGatewayURL(_ url: URL) throws {
        try keychain.save(key: Self.gatewayURLTag, data: url.absoluteString.data(using: .utf8)!)
    }

    /// Load the gateway URL from Keychain.
    func loadGatewayURL() -> URL? {
        guard let data = keychain.load(key: Self.gatewayURLTag),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return URL(string: string)
    }

    /// Whether the device is paired (has a token).
    var isPaired: Bool {
        return loadToken() != nil
    }

    /// Clear all pairing data from Keychain.
    func clearPairing() {
        keychain.delete(key: Self.privateKeyTag)
        keychain.delete(key: Self.publicKeyTag)
        keychain.delete(key: Self.tokenTag)
        keychain.delete(key: Self.gatewayURLTag)
        cachedPrivateKey = nil
        cachedIdentity = nil
    }

    /// Build a node.pair.request JSON-RPC message.
    func buildPairRequestMessage() -> [String: Any]? {
        guard let identity = cachedIdentity else { return nil }

        return [
            "type": "request",
            "method": "node.pair.request",
            "id": UUID().uuidString,
            "params": [
                "nodeId": identity.nodeId,
                "displayName": "Zaap (iPhone)",
                "platform": "iOS",
                "publicKey": identity.publicKeyBase64,
                "caps": ["voice"]
            ] as [String: Any]
        ]
    }

    // MARK: - Private

    private static func sha256Hex(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
