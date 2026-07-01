import XCTest
@testable import Zaap

final class SpO2ReaderTests: XCTestCase {

    func testDailySummaryContainsCorrectValues() {
        let summary = SpO2Reader.DailySpO2Summary(
            date: "2026-03-03",
            minSpO2: 95,
            maxSpO2: 99,
            avgSpO2: 97,
            sampleCount: 1,
            samples: [SpO2Reader.SpO2Sample(percentage: 97, timestamp: Date())]
        )

        XCTAssertEqual(summary.date, "2026-03-03")
        XCTAssertEqual(summary.minSpO2, 95)
        XCTAssertEqual(summary.maxSpO2, 99)
        XCTAssertEqual(summary.avgSpO2, 97)
        XCTAssertEqual(summary.sampleCount, 1)
    }

    func testDailySummaryEncodesCurrentPayloadFieldNames() throws {
        let summary = SpO2Reader.DailySpO2Summary(
            date: "2026-03-03",
            minSpO2: 95,
            maxSpO2: 99,
            avgSpO2: 97,
            sampleCount: 1,
            samples: []
        )

        let data = try JSONEncoder().encode(summary)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["minSpO2"] as? Double, 95)
        XCTAssertEqual(json["maxSpO2"] as? Double, 99)
        XCTAssertEqual(json["avgSpO2"] as? Double, 97)
        XCTAssertEqual(json["sampleCount"] as? Int, 1)
    }

    func testDailySummaryDecodesRoundTrip() throws {
        let jsonString = """
        {"date":"2026-03-03","minSpO2":95.0,"maxSpO2":99.0,"avgSpO2":97.0,"sampleCount":1,"samples":[]}
        """
        let data = jsonString.data(using: .utf8)!
        let summary = try JSONDecoder().decode(SpO2Reader.DailySpO2Summary.self, from: data)

        XCTAssertEqual(summary.minSpO2, 95)
        XCTAssertEqual(summary.maxSpO2, 99)
        XCTAssertEqual(summary.avgSpO2, 97)
        XCTAssertEqual(summary.sampleCount, 1)
    }

    func testSampleIsEncodable() throws {
        let sample = SpO2Reader.SpO2Sample(percentage: 97, timestamp: Date())
        let data = try JSONEncoder().encode(sample)
        XCTAssertFalse(data.isEmpty)
    }
}
