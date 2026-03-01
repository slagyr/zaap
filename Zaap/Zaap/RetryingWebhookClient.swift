import Foundation
import os

/// A decorator around `WebhookPosting` that adds retry queue behavior.
/// - On successful `post()`: triggers drain of any queued items
/// - On failed `post()` (background): enqueues the payload for later retry
/// - On failed `postForeground()`: does NOT enqueue (interactive request, user sees error)
final class RetryingWebhookClient: WebhookPosting, @unchecked Sendable {

    // MARK: - Properties

    private let inner: any WebhookPosting
    let retryQueue: WebhookRetryQueue
    private let drainService: RetryDrainService
    private let logger = Logger(subsystem: "com.zaap.app", category: "RetryingWebhook")

    // MARK: - Init

    init(
        inner: any WebhookPosting,
        retryQueue: WebhookRetryQueue,
        drainService: RetryDrainService
    ) {
        self.inner = inner
        self.retryQueue = retryQueue
        self.drainService = drainService
    }

    // MARK: - WebhookPosting

    /// POST a payload (background). On failure, enqueues for retry. On success, triggers drain.
    func post<T: Encodable>(_ payload: T, to path: String?) async throws {
        do {
            try await inner.post(payload, to: path)
            // Success — trigger drain of any queued items
            await drainService.notifySuccess()
        } catch {
            // Failure — encode and enqueue for later retry
            enqueuePayload(payload, path: path)
            throw error
        }
    }

    /// POST a payload (foreground/interactive). Does NOT enqueue on failure.
    /// On success, triggers drain.
    func postForeground<T: Encodable>(_ payload: T, to path: String?) async throws {
        do {
            try await inner.postForeground(payload, to: path)
            await drainService.notifySuccess()
        } catch {
            // Foreground failures are shown to the user — don't queue silently
            throw error
        }
    }

    // MARK: - Private

    private func enqueuePayload<T: Encodable>(_ payload: T, path: String?) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else {
            logger.error("Failed to encode payload for retry queue")
            return
        }
        retryQueue.enqueue(path: path ?? "", payload: data)
        logger.info("Enqueued failed delivery for retry: \(path ?? "", privacy: .public)")
    }
}
