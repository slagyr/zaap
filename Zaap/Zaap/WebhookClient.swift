import Foundation
import os

/// Posts JSON payloads to a configured webhook endpoint with Bearer token auth.
/// Uses a standard URLSession for all requests.
final class WebhookClient: Sendable {

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
    private let session: URLSession
    let requestLog: RequestLog

    // MARK: - Init

    init(requestLog: RequestLog? = nil) {
        session = URLSession(configuration: .default)
        self.requestLog = requestLog ?? RequestLog.shared
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
    func post<T: Encodable>(_ payload: T, to path: String? = nil) async throws {
        try await send(payload, to: path)
    }

    /// POST an Encodable payload using the foreground session.
    /// Use for interactive requests (Test Connection, Send Now) that need immediate response.
    func postForeground<T: Encodable>(_ payload: T, to path: String? = nil) async throws {
        try await send(payload, to: path)
    }

    // MARK: - Private

    private func send<T: Encodable>(_ payload: T, to path: String?) async throws {
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
            encoder.outputFormatting = .prettyPrinted
            data = try encoder.encode(payload)
        } catch {
            throw WebhookError.encodingFailed(error)
        }

        var request = URLRequest(url: targetURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.bearerToken)", forHTTPHeaderField: "Authorization")

        logger.info("POST \(targetURL.absoluteString, privacy: .public)")

        let requestBodyString = String(data: data, encoding: .utf8) ?? "{}"
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let (responseData, response) = try await session.upload(for: request, from: data)
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            await requestLog.append(RequestLogEntry(
                path: path ?? targetURL.path,
                statusCode: statusCode,
                responseTimeMs: elapsedMs,
                requestBody: requestBodyString
            ))

            try validateResponse(responseData, response)
        } catch let error as WebhookError {
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            let statusCode: Int? = if case .invalidResponse(let code) = error { code } else { nil }

            await requestLog.append(RequestLogEntry(
                path: path ?? targetURL.path,
                statusCode: statusCode,
                responseTimeMs: elapsedMs,
                requestBody: requestBodyString,
                errorMessage: error.localizedDescription
            ))

            throw error
        } catch {
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

            await requestLog.append(RequestLogEntry(
                path: path ?? targetURL.path,
                statusCode: nil,
                responseTimeMs: elapsedMs,
                requestBody: requestBodyString,
                errorMessage: error.localizedDescription
            ))

            throw WebhookError.networkError(error)
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
