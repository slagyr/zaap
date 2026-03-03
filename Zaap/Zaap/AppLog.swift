import Foundation

/// In-memory log buffer for capturing diagnostic output on-device.
/// Thread-safe singleton — all access goes through `shared`.
final class AppLog: @unchecked Sendable {

    static let shared = AppLog()

    private let maxEntries = 5000
    private let lock = NSLock()
    private var _entries: [String] = []

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var entries: [String] {
        lock.withLock { _entries }
    }

    func log(_ message: String) {
        let timestamp = formatter.string(from: Date())
        let entry = "[\(timestamp)] \(message)"
        print(entry)
        lock.withLock {
            _entries.append(entry)
            if _entries.count > maxEntries {
                _entries.removeFirst(_entries.count - maxEntries)
            }
        }
    }

    func clear() {
        lock.withLock { _entries.removeAll() }
    }

    func export() -> String {
        lock.withLock { _entries.joined(separator: "\n") }
    }
}
