import XCTest
@testable import Zaap

final class ActivityReaderTests: XCTestCase {

    func testActivitySummaryEncodesToJSON() throws {
        let summary = ActivityReader.ActivitySummary(
            date: "2026-02-15", steps: 10000,
            distanceMeters: 8000.5, activeEnergyKcal: 450.2,
            timestamp: Date(timeIntervalSince1970: 1000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(summary)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["steps"] as? Int, 10000)
        XCTAssertEqual(json["distanceMeters"] as? Double, 8000.5)
    }

    func testActivityErrorDescriptions() {
        XCTAssertEqual(ActivityReader.ActivityError.healthKitNotAvailable.errorDescription,
                       "HealthKit is not available on this device")
        XCTAssertEqual(ActivityReader.ActivityError.authorizationDenied.errorDescription,
                       "HealthKit activity data access denied")
        XCTAssertEqual(ActivityReader.ActivityError.noData.errorDescription,
                       "No activity data found for the requested period")
    }

    func testInitSetsDefaultState() {
        let reader = ActivityReader()
        XCTAssertFalse(reader.isAuthorized)
        XCTAssertNil(reader.lastError)
    }

    func testActivitySummaryFieldValues() {
        let ts = Date(timeIntervalSince1970: 1000)
        let summary = ActivityReader.ActivitySummary(
            date: "2026-02-19", steps: 0,
            distanceMeters: 0, activeEnergyKcal: 0,
            timestamp: ts
        )
        XCTAssertEqual(summary.date, "2026-02-19")
        XCTAssertEqual(summary.steps, 0)
        XCTAssertEqual(summary.distanceMeters, 0)
        XCTAssertEqual(summary.activeEnergyKcal, 0)
        XCTAssertEqual(summary.timestamp, ts)
    }

    // MARK: - Failure paths (HealthKit unavailable in simulator)

    func testRequestAuthorizationThrowsWhenHealthKitUnavailable() async {
        let reader = ActivityReader()
        do {
            try await reader.requestAuthorization()
            XCTFail("Expected healthKitNotAvailable error")
        } catch {
            XCTAssertEqual(error as? ActivityReader.ActivityError, .healthKitNotAvailable)
        }
    }

    func testFetchTodaySummaryThrowsWhenHealthKitUnavailable() async {
        let reader = ActivityReader()
        do {
            _ = try await reader.fetchTodaySummary()
            XCTFail("Expected healthKitNotAvailable error")
        } catch {
            XCTAssertEqual(error as? ActivityReader.ActivityError, .healthKitNotAvailable)
        }
    }
}
