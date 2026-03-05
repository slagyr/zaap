    func testWebhookPayloadFieldNames() throws {
        let spo2 = SpO2Data(
            minPercentage: 95,
            maxPercentage: 99,
            avgPercentage: 97,
            restingPercentage: 96,
            sampleCount: 200
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(spo2)
        let json = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]

        // Verify JSON keys match gateway expectations
        XCTAssertEqual(json["min"] as? Int, 95)
        XCTAssertEqual(json["max"] as? Int, 99)
        XCTAssertEqual(json["avg"] as? Int, 97)
        XCTAssertEqual(json["resting"] as? Int, 96)
        XCTAssertEqual(json["sampleCount"] as? Int, 200)
    }