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

    func testDailySummaryEncodesWithGatewayFieldNames() throws {
        let summary = RestingHeartRateReader.DailyRestingHRSummary(
            date: "2026-03-03", restingBPM: 62, sampleCount: 1,
            samples: [RestingHeartRateReader.RestingHRSample(bpm: 62, timestamp: Date())]
        )
        let data = try JSONEncoder().encode(summary)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Gateway expects "resting" — NOT "restingBPM"
        XCTAssertEqual(json["resting"] as? Double, 62)
        XCTAssertNil(json["restingBPM"], "restingBPM should not appear in JSON; gateway expects 'resting'")
    }

    func testDailySummaryDecodesFromGatewayFieldNames() throws {
        let jsonString = """
        {"date":"2026-03-03","resting":58.0,"sampleCount":1,"samples":[]}
        """
        let data = jsonString.data(using: .utf8)!
        let summary = try JSONDecoder().decode(RestingHeartRateReader.DailyRestingHRSummary.self, from: data)
        XCTAssertEqual(summary.restingBPM, 58.0)
    }

    func testSampleIsEncodable() throws {
        let sample = RestingHeartRateReader.RestingHRSample(bpm: 55, timestamp: Date())
        let data = try JSONEncoder().encode(sample)
        XCTAssertFalse(data.isEmpty)
    }
}
