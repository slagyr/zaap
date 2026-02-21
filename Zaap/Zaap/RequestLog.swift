import Foundation

/// A single webhook request log entry.
struct RequestLogEntry: Identifiable, Sendable, Codable {
    let id: UUID
    let timestamp: Date
    let path: String
    let statusCode: Int?
    let responseTimeMs: Int
    let requestBody: String
    let errorMessage: String?

    private static let copyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    var copyableText: String {
        var lines: [String] = []
        lines.append("Timestamp: \(Self.copyFormatter.string(from: timestamp))")
        lines.append("Path: \(path)")
        lines.append("Status: \(statusCode.map { "\($0)" } ?? "No response")")
        lines.append("Response Time: \(responseTimeMs)ms")
        if let errorMessage {
            lines.append("Error: \(errorMessage)")
        }
        lines.append("Body: \(requestBody)")
        return lines.joined(separator: "\n")
    }

    var isSuccess: Bool {
        guard let code = statusCode else { return false }
        return (200...299).contains(code)
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        path: String,
        statusCode: Int?,
        responseTimeMs: Int,
        requestBody: String,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.path = path
        self.statusCode = statusCode
        self.responseTimeMs = responseTimeMs
        self.requestBody = requestBody
        self.errorMessage = errorMessage
    }
}

/// Persisted ring buffer holding the last N webhook request log entries.
/// Entries survive app restarts — saved to JSON in Application Support.
@MainActor
final class RequestLog: ObservableObject {
    static let shared = RequestLog()

    @Published private(set) var entries: [RequestLogEntry] = []
    let capacity: Int

    private static var storageURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("request_log.json")
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

    init(capacity: Int = 100) {
        self.capacity = capacity
        self.entries = Self.load()
    }

    func append(_ entry: RequestLogEntry) {
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    private static func load() -> [RequestLogEntry] {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let entries = try? decoder.decode([RequestLogEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private func save() {
        guard let data = try? Self.encoder.encode(entries) else { return }
        let url = Self.storageURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
