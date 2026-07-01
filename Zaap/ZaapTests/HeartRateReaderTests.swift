import XCTest
@testable import Zaap

final class HeartRateReaderTests: XCTestCase {

    func testDailySummaryContainsCorrectValues() {
        let summary = HeartRateReader.DailyHeartRateSummary(
            date: "2026-03-03",
            minBPM: 55,
            maxBPM: 150,
            avgBPM: 72,
            restingBPM: 58,
            sampleCount: 1,
            samples: [HeartRateReader.HeartRateSample(bpm: 72, timestamp: Date())]
        )

        XCTAssertEqual(summary.date, "2026-03-03")
        XCTAssertEqual(summary.minBPM, 55)
        XCTAssertEqual(summary.maxBPM, 150)
        XCTAssertEqual(summary.avgBPM, 72)
        XCTAssertEqual(summary.restingBPM, 58)
        XCTAssertEqual(summary.sampleCount, 1)
    }

    func testDailySummaryEncodesCurrentPayloadFieldNames() throws {
        let summary = HeartRateReader.DailyHeartRateSummary(
            date: "2026-03-03",
            minBPM: 55,
            maxBPM: 150,
            avgBPM: 72,
            restingBPM: 58,
            sampleCount: 1,
            samples: []
        )

        let data = try JSONEncoder().encode(summary)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["minBPM"] as? Double, 55)
        XCTAssertEqual(json["maxBPM"] as? Double, 150)
        XCTAssertEqual(json["avgBPM"] as? Double, 72)
        XCTAssertEqual(json["restingBPM"] as? Double, 58)
        XCTAssertEqual(json["sampleCount"] as? Int, 1)
    }

    func testDailySummaryDecodesRoundTrip() throws {
        let jsonString = """
        {"date":"2026-03-03","minBPM":55.0,"maxBPM":150.0,"avgBPM":72.0,"restingBPM":58.0,"sampleCount":1,"samples":[]}
        """
        let data = jsonString.data(using: .utf8)!
        let summary = try JSONDecoder().decode(HeartRateReader.DailyHeartRateSummary.self, from: data)

        XCTAssertEqual(summary.minBPM, 55)
        XCTAssertEqual(summary.maxBPM, 150)
        XCTAssertEqual(summary.avgBPM, 72)
        XCTAssertEqual(summary.restingBPM, 58)
        XCTAssertEqual(summary.sampleCount, 1)
    }

    func testSampleIsEncodable() throws {
        let sample = HeartRateReader.HeartRateSample(bpm: 72, timestamp: Date())
        let data = try JSONEncoder().encode(sample)
        XCTAssertFalse(data.isEmpty)
    }
}
