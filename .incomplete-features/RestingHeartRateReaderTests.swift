import XCTest
@testable import Zaap

final class RestingHeartRateReaderTests: XCTestCase {

    func testDailySummaryContainsCorrectDate() async throws {
        let summary = RestingHeartRateReader.DailyRestingHRSummary(
            date: "2026-03-03", restingBPM: 58, sampleCount: 1,
            samples: [RestingHeartRateReader.RestingHRSample(bpm: 58, timestamp: Date())]
        )
        XCTAssertEqual(summary.date, "2026-03-03")
        XCTAssertEqual(summary.restingBPM, 58)
        XCTAssertEqual(summary.sampleCount, 1)
    }

    func testDailySummaryIsEncodable() throws {
        let summary = RestingHeartRateReader.DailyRestingHRSummary(
            date: "2026-03-03", restingBPM: 62, sampleCount: 1,
            samples: [RestingHeartRateReader.RestingHRSample(bpm: 62, timestamp: Date())]
        )
        let data = try JSONEncoder().encode(summary)
        XCTAssertFalse(data.isEmpty)
    }

    func testSampleIsEncodable() throws {
        let sample = RestingHeartRateReader.RestingHRSample(bpm: 55, timestamp: Date())
        let data = try JSONEncoder().encode(sample)
        XCTAssertFalse(data.isEmpty)
    }
}
