import Foundation

/// A single webhook request log entry.
struct RequestLogEntry: Identifiable, Sendable {
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

/// Thread-safe in-memory ring buffer holding the last N webhook request log entries.
@MainActor
final class RequestLog: ObservableObject {
    static let shared = RequestLog()

    @Published private(set) var entries: [RequestLogEntry] = []
    let capacity: Int

    init(capacity: Int = 10) {
        self.capacity = capacity
    }

    func append(_ entry: RequestLogEntry) {
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    func clear() {
        entries.removeAll()
    }
}
