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
        let log = RequestLog(capacity: 10, skipLoad: true)
        let entry = RequestLogEntry(path: "/hooks/ping", statusCode: 200, responseTimeMs: 10, requestBody: "{}")
        log.append(entry)
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(log.entries[0].path, "/hooks/ping")
    }

    func testRingBufferEvictsOldestWhenOverCapacity() {
        let log = RequestLog(capacity: 3, skipLoad: true)
        for i in 0..<5 {
            log.append(RequestLogEntry(path: "/hooks/\(i)", statusCode: 200, responseTimeMs: i, requestBody: "{}"))
        }
        XCTAssertEqual(log.entries.count, 3)
        XCTAssertEqual(log.entries[0].path, "/hooks/2")
        XCTAssertEqual(log.entries[2].path, "/hooks/4")
    }

    func testDefaultCapacityIsTen() {
        let log = RequestLog(skipLoad: true)
        XCTAssertEqual(log.capacity, 100)
    }

    func testClearRemovesAllEntries() {
        let log = RequestLog(capacity: 10, skipLoad: true)
        log.append(RequestLogEntry(path: "/hooks/ping", statusCode: 200, responseTimeMs: 10, requestBody: "{}"))
        log.append(RequestLogEntry(path: "/hooks/sleep", statusCode: 200, responseTimeMs: 20, requestBody: "{}"))
        log.clear()
        XCTAssertTrue(log.entries.isEmpty)
    }

    // MARK: - copyableText

    func testCopyableTextIncludesAllFields() {
        let date = Date(timeIntervalSince1970: 1700000000) // 2023-11-14 22:13:20 UTC
        let entry = RequestLogEntry(
            timestamp: date,
            path: "/hooks/location",
            statusCode: 200,
            responseTimeMs: 42,
            requestBody: "{\"lat\":33.4}"
        )
        let text = entry.copyableText
        XCTAssertTrue(text.contains("/hooks/location"))
        XCTAssertTrue(text.contains("200"))
        XCTAssertTrue(text.contains("42ms"))
        XCTAssertTrue(text.contains("{\"lat\":33.4}"))
    }

    func testCopyableTextIncludesErrorWhenPresent() {
        let entry = RequestLogEntry(
            path: "/hooks/fail",
            statusCode: nil,
            responseTimeMs: 100,
            requestBody: "{}",
            errorMessage: "Connection refused"
        )
        let text = entry.copyableText
        XCTAssertTrue(text.contains("Connection refused"))
    }

    func testCopyableTextShowsNoResponseWhenStatusNil() {
        let entry = RequestLogEntry(
            path: "/hooks/fail",
            statusCode: nil,
            responseTimeMs: 100,
            requestBody: "{}"
        )
        let text = entry.copyableText
        XCTAssertTrue(text.contains("No response"))
    }

    // MARK: - summaryLine

    func testSummaryLineFormatSuccess() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let entry = RequestLogEntry(
            timestamp: date,
            path: "/hooks/location",
            statusCode: 200,
            responseTimeMs: 42,
            requestBody: "{}"
        )
        let line = entry.summaryLine
        XCTAssertTrue(line.contains("/hooks/location"))
        XCTAssertTrue(line.contains("42ms"))
        XCTAssertTrue(line.contains("200"))
    }

    func testSummaryLineFormatError() {
        let entry = RequestLogEntry(
            path: "/hooks/sleep",
            statusCode: nil,
            responseTimeMs: 150,
            requestBody: "{}",
            errorMessage: "Connection refused"
        )
        let line = entry.summaryLine
        XCTAssertTrue(line.contains("/hooks/sleep"))
        XCTAssertTrue(line.contains("150ms"))
        XCTAssertTrue(line.contains("Connection refused"))
    }

    func testSummaryLineFormatServerError() {
        let entry = RequestLogEntry(
            path: "/hooks/heartrate",
            statusCode: 500,
            responseTimeMs: 80,
            requestBody: "{}",
            errorMessage: "Server error"
        )
        let line = entry.summaryLine
        XCTAssertTrue(line.contains("500"))
        XCTAssertTrue(line.contains("Server error"))
    }

    func testSummaryLineNoResponseWhenStatusNil() {
        let entry = RequestLogEntry(
            path: "/hooks/fail",
            statusCode: nil,
            responseTimeMs: 100,
            requestBody: "{}"
        )
        let line = entry.summaryLine
        XCTAssertTrue(line.contains("No response"))
    }

    func testEntriesOrderIsChronological() {
        let log = RequestLog(capacity: 10, skipLoad: true)
        let early = Date(timeIntervalSince1970: 1000)
        let late = Date(timeIntervalSince1970: 2000)
        log.append(RequestLogEntry(timestamp: early, path: "/hooks/a", statusCode: 200, responseTimeMs: 10, requestBody: "{}"))
        log.append(RequestLogEntry(timestamp: late, path: "/hooks/b", statusCode: 200, responseTimeMs: 10, requestBody: "{}"))
        XCTAssertEqual(log.entries[0].path, "/hooks/a")
        XCTAssertEqual(log.entries[1].path, "/hooks/b")
    }
}
