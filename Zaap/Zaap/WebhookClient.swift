import Foundation
import os

/// Posts JSON payloads to a configured webhook endpoint with Bearer token auth.
/// Uses a background URLSession so requests complete even when the app is suspended.
final class WebhookClient: NSObject, Sendable {

    // MARK: - Types

    struct Configuration: Sendable {
        let url: URL
        let bearerToken: String
    }

    enum WebhookError: Error, LocalizedError {
        case noConfiguration
        case invalidResponse(statusCode: Int)
        case encodingFailed(Error)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .noConfiguration:
                "Webhook URL or token not configured"
            case .invalidResponse(let code):
                "Server returned HTTP \(code)"
            case .encodingFailed(let error):
                "Failed to encode payload: \(error.localizedDescription)"
            case .networkError(let error):
                "Network error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Properties

    static let shared = WebhookClient()

    private let logger = Logger(subsystem: "com.zaap.app", category: "WebhookClient")
    private let backgroundSession: URLSession

    // MARK: - Init

    override init() {
        let config = URLSessionConfiguration.background(withIdentifier: "com.zaap.webhook")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.shouldUseExtendedBackgroundIdleMode = true
        let delegate = SessionDelegate()
        backgroundSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        super.init()
    }

    // MARK: - Public

    /// Load configuration from UserDefaults.
    func loadConfiguration() -> Configuration? {
        guard let urlString = UserDefaults.standard.string(forKey: "webhookURL"),
              let url = URL(string: urlString),
              let token = UserDefaults.standard.string(forKey: "webhookToken"),
              !token.isEmpty else {
            return nil
        }
        return Configuration(url: url, bearerToken: token)
    }

    /// POST an Encodable payload to the configured webhook endpoint.
    /// Uses the background session so delivery succeeds even if the app is suspended.
    func post<T: Encodable>(_ payload: T, to path: String? = nil) async throws {
        guard let config = loadConfiguration() else {
            throw WebhookError.noConfiguration
        }

        let targetURL: URL
        if let path {
            targetURL = config.url.appending(path: path)
        } else {
            targetURL = config.url
        }

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            data = try encoder.encode(payload)
        } catch {
            throw WebhookError.encodingFailed(error)
        }

        // Write to a temp file — background sessions require upload tasks from file.
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".json")
        try data.write(to: tempFile)

        var request = URLRequest(url: targetURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.bearerToken)", forHTTPHeaderField: "Authorization")

        logger.info("POST \(targetURL.absoluteString, privacy: .public)")

        do {
            let (responseData, response) = try await backgroundSession.upload(for: request, fromFile: tempFile)
            try? FileManager.default.removeItem(at: tempFile)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebhookError.invalidResponse(statusCode: 0)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: responseData, encoding: .utf8) ?? ""
                logger.error("HTTP \(httpResponse.statusCode): \(body, privacy: .public)")
                throw WebhookError.invalidResponse(statusCode: httpResponse.statusCode)
            }

            logger.info("Webhook delivered successfully (HTTP \(httpResponse.statusCode))")
        } catch let error as WebhookError {
            throw error
        } catch {
            try? FileManager.default.removeItem(at: tempFile)
            throw WebhookError.networkError(error)
        }
    }
}

// MARK: - Background Session Delegate

/// Handles background session lifecycle events.
private final class SessionDelegate: NSObject, URLSessionDelegate, URLSessionDataDelegate, Sendable {

    private let logger = Logger(subsystem: "com.zaap.app", category: "WebhookSession")

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        if let error {
            logger.error("Session invalidated: \(error.localizedDescription, privacy: .public)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            logger.error("Task failed: \(error.localizedDescription, privacy: .public)")
        } else {
            logger.info("Background task completed")
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        logger.info("Background session finished events")
        // The app delegate should store and call the completion handler here.
        // That wiring will be done in the background delivery bead (zaap-0a2).
    }
}
