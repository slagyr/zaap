import XCTest
@testable import Zaap

final class SleepDataReaderTests: XCTestCase {

    func testSleepSessionDurationComputedFromDates() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 3600) // 1 hour
        let session = SleepDataReader.SleepSession(
            startDate: start, endDate: end,
            stage: "asleepDeep", durationMinutes: 60
        )
        XCTAssertEqual(session.duration, 3600, accuracy: 0.01)
    }

    func testSleepSummaryEncodesToJSON() throws {
        let summary = SleepDataReader.SleepSummary(
            date: "2026-02-15",
            bedtime: Date(timeIntervalSince1970: 1000),
            wakeTime: Date(timeIntervalSince1970: 29000),
            totalInBedMinutes: 480,
            totalAsleepMinutes: 420,
            deepSleepMinutes: 90,
            remSleepMinutes: 120,
            coreSleepMinutes: 210,
            awakeMinutes: 30,
            sessions: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(summary)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["date"] as? String, "2026-02-15")
        XCTAssertEqual(json["deepSleepMinutes"] as? Int, 90)
    }

    func testSleepErrorDescriptions() {
        XCTAssertEqual(SleepDataReader.SleepError.healthKitNotAvailable.errorDescription,
                       "HealthKit is not available on this device")
        XCTAssertEqual(SleepDataReader.SleepError.noData.errorDescription,
                       "No sleep data found for the requested period")
    }
}
