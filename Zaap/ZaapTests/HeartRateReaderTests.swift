import XCTest
@testable import Zaap

final class HeartRateReaderTests: XCTestCase {

    func testHeartRateSampleEncodesToJSON() throws {
        let sample = HeartRateReader.HeartRateSample(bpm: 72.0, timestamp: Date(timeIntervalSince1970: 1000))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(sample)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["bpm"] as? Double, 72.0)
    }

    func testDailySummaryEncodesToJSON() throws {
        let summary = HeartRateReader.DailyHeartRateSummary(
            date: "2026-02-15", minBPM: 55, maxBPM: 150, avgBPM: 72,
            restingBPM: 58, sampleCount: 100, samples: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(summary)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["minBPM"] as? Double, 55)
        XCTAssertEqual(json["sampleCount"] as? Int, 100)
    }

    func testHeartRateErrorDescriptions() {
        XCTAssertEqual(HeartRateReader.HeartRateError.healthKitNotAvailable.errorDescription,
                       "HealthKit is not available on this device")
        XCTAssertEqual(HeartRateReader.HeartRateError.authorizationDenied.errorDescription,
                       "HealthKit heart rate access denied")
        XCTAssertEqual(HeartRateReader.HeartRateError.noData.errorDescription,
                       "No heart rate data found for the requested period")
    }

    // MARK: - Failure paths (HealthKit unavailable in simulator)

    func testRequestAuthorizationThrowsWhenHealthKitUnavailable() async {
        let reader = HeartRateReader()
        do {
            try await reader.requestAuthorization()
        } catch {
            XCTAssertEqual(error as? HeartRateReader.HeartRateError, .healthKitNotAvailable)
        }
    }

    func testFetchHeartRateSamplesThrowsWhenHealthKitUnavailable() async {
        let reader = HeartRateReader()
        do {
            _ = try await reader.fetchHeartRateSamples()
        } catch {
            XCTAssertEqual(error as? HeartRateReader.HeartRateError, .healthKitNotAvailable)
        }
    }

    func testFetchRestingHeartRateThrowsWhenHealthKitUnavailable() async {
        let reader = HeartRateReader()
        do {
            _ = try await reader.fetchRestingHeartRate()
        } catch {
            XCTAssertEqual(error as? HeartRateReader.HeartRateError, .healthKitNotAvailable)
        }
    }

    func testFetchDailySummaryThrowsWhenHealthKitUnavailable() async {
        let reader = HeartRateReader()
        do {
            _ = try await reader.fetchDailySummary(for: Date())
        } catch {
            XCTAssertEqual(error as? HeartRateReader.HeartRateError, .healthKitNotAvailable)
        }
    }

    func testFetchDailySummaryNoArgThrowsWhenHealthKitUnavailable() async {
        let reader = HeartRateReader()
        do {
            _ = try await reader.fetchDailySummary()
        } catch {
            XCTAssertEqual(error as? HeartRateReader.HeartRateError, .healthKitNotAvailable)
        }
    }

    func testInitSetsDefaultState() {
        let reader = HeartRateReader()
        XCTAssertFalse(reader.isAuthorized)
        XCTAssertNil(reader.lastError)
    }
}
