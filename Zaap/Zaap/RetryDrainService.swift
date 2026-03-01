import Foundation
import os

/// Protocol for posting raw Data payloads to a webhook path.
/// Used by RetryDrainService to replay queued items without re-encoding.
protocol RawPayloadPosting: Sendable {
    func postRawPayload(_ payload: Data, to path: String) async throws
}

/// Drains the WebhookRetryQueue by replaying failed items when connectivity is restored.
/// After any successful webhook POST, call `notifySuccess()` to trigger a drain.
/// Drains one item at a time with a configurable interval between items.
/// Stops draining if an item fails; resumes on the next `notifySuccess()`.
final class RetryDrainService {

    // MARK: - Properties

    private let queue: WebhookRetryQueue
    private let poster: any RawPayloadPosting
    private let drainInterval: TimeInterval
    private let logger = Logger(subsystem: "com.zaap.app", category: "RetryDrain")

    private(set) var isDraining = false

    // MARK: - Init

    /// - Parameters:
    ///   - queue: The retry queue to drain items from.
    ///   - poster: The poster used to replay queued payloads.
    ///   - drainInterval: Seconds between each drain attempt (default 5s).
    init(
        queue: WebhookRetryQueue,
        poster: any RawPayloadPosting,
        drainInterval: TimeInterval = 5
    ) {
        self.queue = queue
        self.poster = poster
        self.drainInterval = drainInterval
    }

    // MARK: - Public

    /// Call after any successful webhook POST to trigger a drain of the retry queue.
    /// Processes items one at a time, oldest first, with `drainInterval` between each.
    /// Stops immediately if a drain item fails (network still down).
    func notifySuccess() async {
        guard !queue.isEmpty else { return }
        guard !isDraining else { return }

        isDraining = true
        defer { isDraining = false }

        while let item = queue.dequeue() {
            do {
                try await poster.postRawPayload(item.payload, to: item.path)
                logger.info("Drain: delivered queued item to \(item.path, privacy: .public)")

                // Wait before next item (unless queue is now empty)
                if !queue.isEmpty && drainInterval > 0 {
                    try await Task.sleep(nanoseconds: UInt64(drainInterval * 1_000_000_000))
                }
            } catch {
                logger.warning("Drain: failed to deliver \(item.path, privacy: .public), stopping drain")
                // Put the failed item back at the front
                queue.requeueAtFront(item)
                return
            }
        }
    }
}
