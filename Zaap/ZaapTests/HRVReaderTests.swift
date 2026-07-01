import XCTest
@testable import Zaap

final class HRVReaderTests: XCTestCase {

    func testDailySummaryContainsCorrectValues() {
        let summary = HRVReader.DailyHRVSummary(
            date: "2026-03-03",
            minSDNN: 20,
            maxSDNN: 80,
            avgSDNN: 45,
            sampleCount: 1,
            samples: [HRVReader.HRVSample(sdnn: 45, timestamp: Date())]
        )

        XCTAssertEqual(summary.date, "2026-03-03")
        XCTAssertEqual(summary.minSDNN, 20)
        XCTAssertEqual(summary.maxSDNN, 80)
        XCTAssertEqual(summary.avgSDNN, 45)
        XCTAssertEqual(summary.sampleCount, 1)
    }

    func testDailySummaryEncodesCurrentPayloadFieldNames() throws {
        let summary = HRVReader.DailyHRVSummary(
            date: "2026-03-03",
            minSDNN: 20,
            maxSDNN: 80,
            avgSDNN: 45,
            sampleCount: 1,
            samples: []
        )

        let data = try JSONEncoder().encode(summary)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["minSDNN"] as? Double, 20)
        XCTAssertEqual(json["maxSDNN"] as? Double, 80)
        XCTAssertEqual(json["avgSDNN"] as? Double, 45)
        XCTAssertEqual(json["sampleCount"] as? Int, 1)
    }

    func testDailySummaryDecodesRoundTrip() throws {
        let jsonString = """
        {"date":"2026-03-03","minSDNN":20.0,"maxSDNN":80.0,"avgSDNN":45.0,"sampleCount":1,"samples":[]}
        """
        let data = jsonString.data(using: .utf8)!
        let summary = try JSONDecoder().decode(HRVReader.DailyHRVSummary.self, from: data)

        XCTAssertEqual(summary.minSDNN, 20)
        XCTAssertEqual(summary.maxSDNN, 80)
        XCTAssertEqual(summary.avgSDNN, 45)
        XCTAssertEqual(summary.sampleCount, 1)
    }

    func testSampleIsEncodable() throws {
        let sample = HRVReader.HRVSample(sdnn: 45, timestamp: Date())
        let data = try JSONEncoder().encode(sample)
        XCTAssertFalse(data.isEmpty)
    }
}
