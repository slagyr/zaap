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
        XCTAssertEqual(ActivityReader.ActivityError.noData.errorDescription,
                       "No activity data found for the requested period")
    }
}
