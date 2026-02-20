import XCTest
@testable import Zaap

@MainActor
final class RequestLogTests: XCTestCase {

    // MARK: - RequestLogEntry

    func testEntryIsSuccessForStatusIn200Range() {
        let entry = RequestLogEntry(path: "/hooks/location", statusCode: 200, responseTimeMs: 50, requestBody: "{}")
        XCTAssertTrue(entry.isSuccess)

        let entry299 = RequestLogEntry(path: "/hooks/sleep", statusCode: 299, responseTimeMs: 50, requestBody: "{}")
        XCTAssertTrue(entry299.isSuccess)
    }

    func testEntryIsNotSuccessForNon200Status() {
        let entry = RequestLogEntry(path: "/hooks/location", statusCode: 500, responseTimeMs: 50, requestBody: "{}")
        XCTAssertFalse(entry.isSuccess)
    }

    func testEntryIsNotSuccessWhenStatusCodeNil() {
        let entry = RequestLogEntry(path: "/hooks/location", statusCode: nil, responseTimeMs: 50, requestBody: "{}", errorMessage: "Network error")
        XCTAssertFalse(entry.isSuccess)
    }

    // MARK: - RequestLog ring buffer

    func testAppendAddsEntry() {
        let log = RequestLog(capacity: 10)
        let entry = RequestLogEntry(path: "/hooks/ping", statusCode: 200, responseTimeMs: 10, requestBody: "{}")
        log.append(entry)
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(log.entries[0].path, "/hooks/ping")
    }

    func testRingBufferEvictsOldestWhenOverCapacity() {
        let log = RequestLog(capacity: 3)
        for i in 0..<5 {
            log.append(RequestLogEntry(path: "/hooks/\(i)", statusCode: 200, responseTimeMs: i, requestBody: "{}"))
        }
        XCTAssertEqual(log.entries.count, 3)
        XCTAssertEqual(log.entries[0].path, "/hooks/2")
        XCTAssertEqual(log.entries[2].path, "/hooks/4")
    }

    func testDefaultCapacityIsTen() {
        let log = RequestLog()
        XCTAssertEqual(log.capacity, 10)
    }

    func testClearRemovesAllEntries() {
        let log = RequestLog(capacity: 10)
        log.append(RequestLogEntry(path: "/hooks/ping", statusCode: 200, responseTimeMs: 10, requestBody: "{}"))
        log.append(RequestLogEntry(path: "/hooks/sleep", statusCode: 200, responseTimeMs: 20, requestBody: "{}"))
        log.clear()
        XCTAssertTrue(log.entries.isEmpty)
    }

    func testEntriesOrderIsChronological() {
        let log = RequestLog(capacity: 10)
        let early = Date(timeIntervalSince1970: 1000)
        let late = Date(timeIntervalSince1970: 2000)
        log.append(RequestLogEntry(timestamp: early, path: "/hooks/a", statusCode: 200, responseTimeMs: 10, requestBody: "{}"))
        log.append(RequestLogEntry(timestamp: late, path: "/hooks/b", statusCode: 200, responseTimeMs: 10, requestBody: "{}"))
        XCTAssertEqual(log.entries[0].path, "/hooks/a")
        XCTAssertEqual(log.entries[1].path, "/hooks/b")
    }
}
