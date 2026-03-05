    func testWebhookPayloadFieldNames() throws {
        let hr = HeartRateData(
            minBPM: 60,
            maxBPM: 120,
            avgBPM: 80,
            restingBPM: 65,
            sampleCount: 100
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(hr)
        let json = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]

        // Verify JSON keys match gateway expectations
        XCTAssertEqual(json["min"] as? Int, 60)
        XCTAssertEqual(json["max"] as? Int, 120)
        XCTAssertEqual(json["avg"] as? Int, 80)
        XCTAssertEqual(json["resting"] as? Int, 65)
        XCTAssertEqual(json["sampleCount"] as? Int, 100)
    }