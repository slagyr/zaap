    func testWebhookPayloadFieldNames() throws {
        let hrv = HRVData(
            minSDNN: 10.5,
            maxSDNN: 50.2,
            avgSDNN: 25.8,
            restingSDNN: 15.3,
            sampleCount: 50
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(hrv)
        let json = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]

        // Verify JSON keys match gateway expectations
        XCTAssertEqual(json["min"] as? Double, 10.5)
        XCTAssertEqual(json["max"] as? Double, 50.2)
        XCTAssertEqual(json["avg"] as? Double, 25.8)
        XCTAssertEqual(json["resting"] as? Double, 15.3)
        XCTAssertEqual(json["sampleCount"] as? Int, 50)
    }