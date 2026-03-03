import XCTest
@testable import Zaap

@MainActor
final class AppLogTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AppLog.shared.clear()
    }

    func testLogAppendsEntry() {
        AppLog.shared.log("Hello")
        XCTAssertEqual(AppLog.shared.entries.count, 1)
        XCTAssertTrue(AppLog.shared.entries[0].contains("Hello"))
    }

    func testLogAppendsMultipleEntries() {
        AppLog.shared.log("First")
        AppLog.shared.log("Second")
        XCTAssertEqual(AppLog.shared.entries.count, 2)
        XCTAssertTrue(AppLog.shared.entries[0].contains("First"))
        XCTAssertTrue(AppLog.shared.entries[1].contains("Second"))
    }

    func testClearRemovesAllEntries() {
        AppLog.shared.log("Hello")
        AppLog.shared.log("World")
        AppLog.shared.clear()
        XCTAssertTrue(AppLog.shared.entries.isEmpty)
    }

    func testLogCapsAtMaxEntries() {
        for i in 0..<1100 {
            AppLog.shared.log("Entry \(i)")
        }
        XCTAssertEqual(AppLog.shared.entries.count, 1000)
        // Oldest entries should be dropped
        XCTAssertTrue(AppLog.shared.entries[0].contains("Entry 100"))
        XCTAssertTrue(AppLog.shared.entries.last?.contains("Entry 1099") ?? false)
    }

    func testExportReturnsNewlineSeparatedEntries() {
        AppLog.shared.log("Alpha")
        AppLog.shared.log("Beta")
        let exported = AppLog.shared.export()
        XCTAssertTrue(exported.contains("Alpha"))
        XCTAssertTrue(exported.contains("Beta"))
        XCTAssertTrue(exported.contains("\n"))
    }

    func testEntriesIncludeTimestamp() {
        AppLog.shared.log("Timestamped")
        let entry = AppLog.shared.entries[0]
        // Should have a bracketed timestamp prefix like [15:30:45]
        XCTAssertTrue(entry.hasPrefix("["), "Entry should start with timestamp bracket: \(entry)")
    }
}
