import XCTest
import SwiftData
@testable import Zaap

final class DeliveryLogServiceTests: XCTestCase {

    var container: ModelContainer!
    var service: DeliveryLogService!

    @MainActor
    override func setUp() {
        super.setUp()
        let schema = Schema([DeliveryRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        service = DeliveryLogService(context: container.mainContext)
    }

    override func tearDown() {
        container = nil
        service = nil
        super.tearDown()
    }

    // MARK: - DeliveryDataType enum

    func testDataTypeHasAllCases() {
        let cases = DeliveryDataType.allCases
        XCTAssertEqual(cases.count, 5)
        XCTAssertTrue(cases.contains(.location))
        XCTAssertTrue(cases.contains(.sleep))
        XCTAssertTrue(cases.contains(.heartRate))
        XCTAssertTrue(cases.contains(.activity))
        XCTAssertTrue(cases.contains(.workout))
    }

    // MARK: - Recording deliveries

    @MainActor
    func testRecordSuccessfulDelivery() throws {
        let now = Date()
        service.record(dataType: .location, timestamp: now, success: true)

        let descriptor = FetchDescriptor<DeliveryRecord>()
        let records = try container.mainContext.fetch(descriptor)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].dataType, .location)
        XCTAssertEqual(records[0].timestamp, now)
        XCTAssertTrue(records[0].success)
        XCTAssertNil(records[0].errorMessage)
    }

    @MainActor
    func testRecordFailedDeliveryWithError() throws {
        let now = Date()
        service.record(dataType: .sleep, timestamp: now, success: false, errorMessage: "timeout")

        let descriptor = FetchDescriptor<DeliveryRecord>()
        let records = try container.mainContext.fetch(descriptor)
        XCTAssertEqual(records.count, 1)
        XCTAssertFalse(records[0].success)
        XCTAssertEqual(records[0].errorMessage, "timeout")
    }

    @MainActor
    func testRecordMultipleDeliveries() throws {
        service.record(dataType: .heartRate, timestamp: Date(), success: true)
        service.record(dataType: .activity, timestamp: Date(), success: false, errorMessage: "fail")
        service.record(dataType: .workout, timestamp: Date(), success: true)

        let descriptor = FetchDescriptor<DeliveryRecord>()
        let records = try container.mainContext.fetch(descriptor)
        XCTAssertEqual(records.count, 3)
    }

    // MARK: - Query grouped by type and day

    @MainActor
    func testQueryGroupedReturnsEmptyForNoRecords() throws {
        let result = try service.recordsGroupedByTypeAndDay(lastDays: 7)
        XCTAssertTrue(result.isEmpty)
    }

    @MainActor
    func testQueryGroupedReturnsTodaysRecords() throws {
        let now = Date()
        service.record(dataType: .location, timestamp: now, success: true)
        service.record(dataType: .location, timestamp: now, success: false, errorMessage: "err")

        let result = try service.recordsGroupedByTypeAndDay(lastDays: 1)
        XCTAssertEqual(result.count, 1) // one type
        let key = result.keys.first!
        XCTAssertEqual(key.dataType, .location)
        XCTAssertEqual(result[key]!.count, 2)
    }

    @MainActor
    func testQueryGroupedByMultipleTypes() throws {
        let now = Date()
        service.record(dataType: .location, timestamp: now, success: true)
        service.record(dataType: .sleep, timestamp: now, success: true)

        let result = try service.recordsGroupedByTypeAndDay(lastDays: 1)
        XCTAssertEqual(result.count, 2)
    }

    @MainActor
    func testQueryGroupedExcludesOldRecords() throws {
        let old = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let now = Date()
        service.record(dataType: .location, timestamp: old, success: true)
        service.record(dataType: .location, timestamp: now, success: true)

        let result = try service.recordsGroupedByTypeAndDay(lastDays: 3)
        let totalRecords = result.values.flatMap { $0 }
        XCTAssertEqual(totalRecords.count, 1)
    }

    @MainActor
    func testQueryGroupedSeparatesDays() throws {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        service.record(dataType: .location, timestamp: today, success: true)
        service.record(dataType: .location, timestamp: yesterday, success: true)

        let result = try service.recordsGroupedByTypeAndDay(lastDays: 7)
        XCTAssertEqual(result.count, 2) // same type, different days = 2 keys
    }
}
