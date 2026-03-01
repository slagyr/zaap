import Foundation
import os

/// A single item queued for webhook retry delivery.
struct RetryQueueItem: Identifiable, Codable, Sendable {
    let id: UUID
    let path: String
    let payload: Data
    let originalTimestamp: Date

    init(
        id: UUID = UUID(),
        path: String,
        payload: Data,
        originalTimestamp: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.payload = payload
        self.originalTimestamp = originalTimestamp
    }

}

/// Persistent queue for failed webhook deliveries.
/// Failed POSTs are stored to disk and retried when connectivity is restored.
final class WebhookRetryQueue {

    // MARK: - Constants

    static let defaultMaxSize = 500
    static let ttlSeconds: TimeInterval = 7 * 24 * 60 * 60 // 7 days

    // MARK: - Properties

    private(set) var items: [RetryQueueItem] = []
    let maxSize: Int

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    /// Called after any mutation that changes the item count.
    var onCountChange: ((Int) -> Void)?

    private let skipLoad: Bool

    // MARK: - Init

    init(maxSize: Int = defaultMaxSize, skipLoad: Bool = false) {
        self.maxSize = maxSize
        self.skipLoad = skipLoad
        if !skipLoad {
            items = Self.load()
        }
    }

    // MARK: - Public

    /// Enqueue a failed delivery for later retry.
    /// Deduplicates by path + payload content. Drops oldest if over max size.
    func enqueue(path: String, payload: Data, originalTimestamp: Date = Date()) {
        let item = RetryQueueItem(path: path, payload: payload, originalTimestamp: originalTimestamp)

        // Deduplication: skip if an identical path+payload is already queued
        let isDuplicate = items.contains { $0.path == item.path && $0.payload == item.payload }
        guard !isDuplicate else { return }

        items.append(item)

        // Cap enforcement: drop oldest when over max
        if items.count > maxSize {
            items.removeFirst(items.count - maxSize)
        }

        save()
        onCountChange?(count)
    }

    /// Remove and return the oldest item from the queue.
    func dequeue() -> RetryQueueItem? {
        guard !items.isEmpty else { return nil }
        let item = items.removeFirst()
        save()
        onCountChange?(count)
        return item
    }

    /// Re-insert an item at the front of the queue (for failed drain retries).
    func requeueAtFront(_ item: RetryQueueItem) {
        items.insert(item, at: 0)
        save()
        onCountChange?(count)
    }

    /// Remove items older than the TTL (7 days by default).
    func pruneExpired(ttl: TimeInterval = ttlSeconds) {
        let cutoff = Date().addingTimeInterval(-ttl)
        items.removeAll { $0.originalTimestamp < cutoff }
        save()
        onCountChange?(count)
    }

    // MARK: - Persistence

    private static var storageURL: URL {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("retry_queue.json")
        }
        return dir.appendingPathComponent("retry_queue.json")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static func load() -> [RetryQueueItem] {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let items = try? decoder.decode([RetryQueueItem].self, from: data) else {
            return []
        }
        return items
    }

    private func save() {
        guard !skipLoad else { return }
        guard let data = try? Self.encoder.encode(items) else { return }
        let url = Self.storageURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
