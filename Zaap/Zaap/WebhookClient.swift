import Foundation
import os

/// Posts JSON payloads to a configured webhook endpoint with Bearer token auth.
/// Uses a background URLSession for automatic deliveries (survives app suspension)
/// and a standard URLSession for interactive requests (Test Connection, Send Now).
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
    private let foregroundSession: URLSession

    // MARK: - Init

    override init() {
        let bgConfig = URLSessionConfiguration.background(withIdentifier: "com.zaap.webhook")
        bgConfig.isDiscretionary = false
        bgConfig.sessionSendsLaunchEvents = true
        bgConfig.shouldUseExtendedBackgroundIdleMode = true
        let delegate = SessionDelegate()
        backgroundSession = URLSession(configuration: bgConfig, delegate: delegate, delegateQueue: nil)
        foregroundSession = URLSession(configuration: .default)
        super.init()
    }

    // MARK: - Public

    /// Load configuration from SettingsManager.
    func loadConfiguration() -> Configuration? {
        let settings = SettingsManager.shared
        guard let url = settings.webhookURLValue, settings.isConfigured else {
            return nil
        }
        return Configuration(url: url, bearerToken: settings.authToken)
    }

    /// POST an Encodable payload to the configured webhook endpoint.
    /// Uses the background session so delivery succeeds even if the app is suspended.
    func post<T: Encodable>(_ payload: T, to path: String? = nil) async throws {
        try await send(payload, to: path, useBackground: true)
    }

    /// POST an Encodable payload using the foreground session.
    /// Use for interactive requests (Test Connection, Send Now) that need immediate response.
    func postForeground<T: Encodable>(_ payload: T, to path: String? = nil) async throws {
        try await send(payload, to: path, useBackground: false)
    }

    // MARK: - Private

    private func send<T: Encodable>(_ payload: T, to path: String?, useBackground: Bool) async throws {
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

        var request = URLRequest(url: targetURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.bearerToken)", forHTTPHeaderField: "Authorization")

        logger.info("POST \(targetURL.absoluteString, privacy: .public) [bg=\(useBackground)]")

        if useBackground {
            // Background sessions require upload from file
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".json")
            try data.write(to: tempFile)

            do {
                let (responseData, response) = try await backgroundSession.upload(for: request, fromFile: tempFile)
                try? FileManager.default.removeItem(at: tempFile)
                try validateResponse(responseData, response)
            } catch let error as WebhookError {
                throw error
            } catch {
                try? FileManager.default.removeItem(at: tempFile)
                throw WebhookError.networkError(error)
            }
        } else {
            // Foreground session — standard data upload, safe with async/await
            do {
                let (responseData, response) = try await foregroundSession.upload(for: request, from: data)
                try validateResponse(responseData, response)
            } catch let error as WebhookError {
                throw error
            } catch {
                throw WebhookError.networkError(error)
            }
        }
    }

    private func validateResponse(_ responseData: Data, _ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebhookError.invalidResponse(statusCode: 0)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: responseData, encoding: .utf8) ?? ""
            logger.error("HTTP \(httpResponse.statusCode): \(body, privacy: .public)")
            throw WebhookError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        logger.info("Webhook delivered successfully (HTTP \(httpResponse.statusCode))")
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
    }
}
