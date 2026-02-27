import HealthKit
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
        XCTAssertEqual(SleepDataReader.SleepError.authorizationDenied.errorDescription,
                       "HealthKit sleep data access denied")
        XCTAssertEqual(SleepDataReader.SleepError.noData.errorDescription,
                       "No sleep data found for the requested period")
    }

    // MARK: - Failure paths (HealthKit unavailable in simulator)

    func testRequestAuthorizationThrowsWhenHealthKitUnavailable() async throws {
        try XCTSkipIf(HKHealthStore.isHealthDataAvailable(), "HealthKit is available on this simulator")
        let reader = SleepDataReader()
        do {
            try await reader.requestAuthorization()
        } catch {
            XCTAssertEqual(error as? SleepDataReader.SleepError, .healthKitNotAvailable)
        }
    }

    func testFetchSleepSamplesThrowsWhenHealthKitUnavailable() async throws {
        try XCTSkipIf(HKHealthStore.isHealthDataAvailable(), "HealthKit is available on this simulator")
        let reader = SleepDataReader()
        do {
            _ = try await reader.fetchSleepSamples()
        } catch {
            XCTAssertEqual(error as? SleepDataReader.SleepError, .healthKitNotAvailable)
        }
    }

    func testFetchLastNightSummaryThrowsWhenHealthKitUnavailable() async throws {
        try XCTSkipIf(HKHealthStore.isHealthDataAvailable(), "HealthKit is available on this simulator")
        let reader = SleepDataReader()
        do {
            _ = try await reader.fetchLastNightSummary()
        } catch {
            XCTAssertEqual(error as? SleepDataReader.SleepError, .healthKitNotAvailable)
        }
    }

    func testSleepSessionEncodesToJSON() throws {
        let session = SleepDataReader.SleepSession(
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 3600),
            stage: "asleepDeep",
            durationMinutes: 60
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["stage"] as? String, "asleepDeep")
        XCTAssertEqual(json["durationMinutes"] as? Int, 60)
    }

    func testInitSetsDefaultState() {
        let reader = SleepDataReader()
        XCTAssertFalse(reader.isAuthorized)
        XCTAssertNil(reader.lastError)
    }

    // MARK: - Mock reader failure paths

    func testMockReaderThrowsNoDataWhenSummaryNotSet() async {
        let reader = MockSleepReader()
        // summaryToReturn is nil by default → fetchLastNightSummary should throw noData
        do {
            _ = try await reader.fetchLastNightSummary()
            XCTFail("Expected noData error")
        } catch {
            XCTAssertEqual(error as? SleepDataReader.SleepError, .noData)
        }
    }

    func testMockReaderThrowsAuthorizationDeniedOnFetch() async {
        let reader = MockSleepReader()
        reader.shouldThrow = SleepDataReader.SleepError.authorizationDenied
        do {
            _ = try await reader.fetchLastNightSummary()
            XCTFail("Expected authorizationDenied error")
        } catch {
            XCTAssertEqual(error as? SleepDataReader.SleepError, .authorizationDenied)
        }
    }

    func testMockReaderThrowsAuthorizationDeniedOnRequestAuthorization() async {
        let reader = MockSleepReader()
        reader.shouldThrow = SleepDataReader.SleepError.authorizationDenied
        do {
            try await reader.requestAuthorization()
            XCTFail("Expected authorizationDenied error")
        } catch {
            XCTAssertEqual(error as? SleepDataReader.SleepError, .authorizationDenied)
        }
    }

    func testMockReaderPropagatesNetworkStyleError() async {
        let reader = MockSleepReader()
        reader.shouldThrow = URLError(.notConnectedToInternet)
        do {
            _ = try await reader.fetchLastNightSummary()
            XCTFail("Expected URLError")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func testMockReaderReturnsSummaryWhenSet() async throws {
        let reader = MockSleepReader()
        reader.summaryToReturn = SleepDataReader.SleepSummary(
            date: "2026-02-19", bedtime: nil, wakeTime: nil,
            totalInBedMinutes: 480, totalAsleepMinutes: 420,
            deepSleepMinutes: 90, remSleepMinutes: 120,
            coreSleepMinutes: 210, awakeMinutes: 30, sessions: []
        )
        let summary = try await reader.fetchLastNightSummary()
        XCTAssertEqual(summary.date, "2026-02-19")
        XCTAssertEqual(summary.totalAsleepMinutes, 420)
    }
}
