import XCTest
@testable import Zaap

final class RespiratoryRateReaderTests: XCTestCase {

    func testDailySummaryContainsCorrectDate() async throws {
        let summary = RespiratoryRateReader.DailyRespiratoryRateSummary(
            date: "2026-03-03", minRate: 12.0, maxRate: 18.0, avgRate: 15.0,
            sampleCount: 3,
            samples: [RespiratoryRateReader.RespiratoryRateSample(breathsPerMinute: 15.0, timestamp: Date())]
        )
        XCTAssertEqual(summary.date, "2026-03-03")
        XCTAssertEqual(summary.minRate, 12.0)
        XCTAssertEqual(summary.maxRate, 18.0)
        XCTAssertEqual(summary.avgRate, 15.0)
    }

    func testDailySummaryEncodesWithGatewayFieldNames() throws {
        let summary = RespiratoryRateReader.DailyRespiratoryRateSummary(
            date: "2026-03-03", minRate: 12.0, maxRate: 20.0, avgRate: 16.0,
            sampleCount: 2,
            samples: []
        )
        let data = try JSONEncoder().encode(summary)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Gateway expects "min", "max", "avg" — NOT "minRate", "maxRate", "avgRate"
        XCTAssertEqual(json["min"] as? Double, 12.0)
        XCTAssertEqual(json["max"] as? Double, 20.0)
        XCTAssertEqual(json["avg"] as? Double, 16.0)
        XCTAssertNil(json["minRate"], "minRate should not appear in JSON; gateway expects 'min'")
        XCTAssertNil(json["maxRate"], "maxRate should not appear in JSON; gateway expects 'max'")
        XCTAssertNil(json["avgRate"], "avgRate should not appear in JSON; gateway expects 'avg'")
    }

    func testDailySummaryDecodesFromGatewayFieldNames() throws {
        let jsonString = """
        {"date":"2026-03-03","min":10.0,"max":22.0,"avg":16.0,"sampleCount":1,"samples":[]}
        """
        let data = jsonString.data(using: .utf8)!
        let summary = try JSONDecoder().decode(RespiratoryRateReader.DailyRespiratoryRateSummary.self, from: data)
        XCTAssertEqual(summary.minRate, 10.0)
        XCTAssertEqual(summary.maxRate, 22.0)
        XCTAssertEqual(summary.avgRate, 16.0)
    }

    func testSampleIsEncodable() throws {
        let sample = RespiratoryRateReader.RespiratoryRateSample(breathsPerMinute: 14.5, timestamp: Date())
        let data = try JSONEncoder().encode(sample)
        XCTAssertFalse(data.isEmpty)
    }
}
