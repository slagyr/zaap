import XCTest
@testable import Zaap

final class HRVReaderTests: XCTestCase {

    func testHRVSampleHasExpectedFields() {
        let sample = HRVReader.HRVSample(sdnn: 42.5, timestamp: Date())
        XCTAssertEqual(sample.sdnn, 42.5)
    }

    func testDailySummaryEncodesCorrectly() throws {
        let summary = HRVReader.DailyHRVSummary(
            date: "2026-03-03",
            minSDNN: 20.0, maxSDNN: 80.0, avgSDNN: 45.0,
            sampleCount: 5,
            samples: [HRVReader.HRVSample(sdnn: 45.0, timestamp: Date())]
        )
        let data = try JSONEncoder().encode(summary)
        XCTAssertFalse(data.isEmpty)
    }

    func testDailySummaryDecodesRoundTrip() throws {
        let original = HRVReader.DailyHRVSummary(
            date: "2026-03-03",
            minSDNN: 20.0, maxSDNN: 80.0, avgSDNN: 45.0,
            sampleCount: 1,
            samples: [HRVReader.HRVSample(sdnn: 45.0, timestamp: Date())]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HRVReader.DailyHRVSummary.self, from: data)
        XCTAssertEqual(decoded.date, "2026-03-03")
        XCTAssertEqual(decoded.minSDNN, 20.0)
        XCTAssertEqual(decoded.maxSDNN, 80.0)
        XCTAssertEqual(decoded.avgSDNN, 45.0)
        XCTAssertEqual(decoded.sampleCount, 1)
    }

    func testMockReaderReturnsConfiguredSummary() async throws {
        let reader = MockHRVReader()
        reader.summaryToReturn = HRVReader.DailyHRVSummary(
            date: "2026-03-03", minSDNN: 20, maxSDNN: 80, avgSDNN: 45,
            sampleCount: 3, samples: []
        )
        let summary = try await reader.fetchDailySummary(for: Date())
        XCTAssertEqual(summary.avgSDNN, 45.0)
    }

    func testMockReaderThrowsNoDataWhenNilSummary() async {
        let reader = MockHRVReader()
        do {
            _ = try await reader.fetchDailySummary(for: Date())
            XCTFail("Expected noData error")
        } catch {
            XCTAssertEqual(error as? HRVReader.HRVError, .noData)
        }
    }

    func testMockReaderThrowsConfiguredError() async {
        let reader = MockHRVReader()
        reader.shouldThrow = HRVReader.HRVError.authorizationDenied
        do {
            _ = try await reader.fetchDailySummary(for: Date())
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? HRVReader.HRVError, .authorizationDenied)
        }
    }

    func testDefaultFetchDailySummaryUsesToday() async throws {
        let reader = MockHRVReader()
        reader.summaryToReturn = HRVReader.DailyHRVSummary(
            date: "2026-03-03", minSDNN: 20, maxSDNN: 80, avgSDNN: 45,
            sampleCount: 1, samples: []
        )
        let summary = try await reader.fetchDailySummary()
        XCTAssertEqual(summary.sampleCount, 1)
    }
}
