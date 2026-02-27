import HealthKit
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

    func testRequestAuthorizationThrowsWhenHealthKitUnavailable() async throws {
        try XCTSkipIf(HKHealthStore.isHealthDataAvailable(), "HealthKit is available on this simulator")
        let reader = ActivityReader()
        do {
            try await reader.requestAuthorization()
            XCTFail("Expected healthKitNotAvailable error")
        } catch {
            XCTAssertEqual(error as? ActivityReader.ActivityError, .healthKitNotAvailable)
        }
    }

    func testFetchTodaySummaryThrowsWhenHealthKitUnavailable() async throws {
        try XCTSkipIf(HKHealthStore.isHealthDataAvailable(), "HealthKit is available on this simulator")
        let reader = ActivityReader()
        do {
            _ = try await reader.fetchTodaySummary()
            XCTFail("Expected healthKitNotAvailable error")
        } catch {
            XCTAssertEqual(error as? ActivityReader.ActivityError, .healthKitNotAvailable)
        }
    }

    // MARK: - Mock reader failure paths

    func testMockReaderThrowsNoDataWhenSummaryNotSet() async {
        let reader = MockActivityReader()
        // summaryToReturn is nil by default → fetchTodaySummary should throw noData
        do {
            _ = try await reader.fetchTodaySummary()
            XCTFail("Expected noData error")
        } catch {
            XCTAssertEqual(error as? ActivityReader.ActivityError, .noData)
        }
    }

    func testMockReaderThrowsAuthorizationDeniedOnFetch() async {
        let reader = MockActivityReader()
        reader.shouldThrow = ActivityReader.ActivityError.authorizationDenied
        do {
            _ = try await reader.fetchTodaySummary()
            XCTFail("Expected authorizationDenied error")
        } catch {
            XCTAssertEqual(error as? ActivityReader.ActivityError, .authorizationDenied)
        }
    }

    func testMockReaderThrowsAuthorizationDeniedOnRequestAuthorization() async {
        let reader = MockActivityReader()
        reader.shouldThrow = ActivityReader.ActivityError.authorizationDenied
        do {
            try await reader.requestAuthorization()
            XCTFail("Expected authorizationDenied error")
        } catch {
            XCTAssertEqual(error as? ActivityReader.ActivityError, .authorizationDenied)
        }
    }

    func testMockReaderPropagatesNetworkStyleError() async {
        let reader = MockActivityReader()
        reader.shouldThrow = URLError(.notConnectedToInternet)
        do {
            _ = try await reader.fetchTodaySummary()
            XCTFail("Expected URLError")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func testMockReaderReturnsSummaryWhenSet() async throws {
        let reader = MockActivityReader()
        reader.summaryToReturn = ActivityReader.ActivitySummary(
            date: "2026-02-19", steps: 8000,
            distanceMeters: 6400, activeEnergyKcal: 350,
            timestamp: Date(timeIntervalSince1970: 1000)
        )
        let summary = try await reader.fetchTodaySummary()
        XCTAssertEqual(summary.date, "2026-02-19")
        XCTAssertEqual(summary.steps, 8000)
    }
}
