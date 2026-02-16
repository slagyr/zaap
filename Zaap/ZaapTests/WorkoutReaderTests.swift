import XCTest
@testable import Zaap

final class WorkoutReaderTests: XCTestCase {

    func testWorkoutSessionEncodesToJSON() throws {
        let session = WorkoutReader.WorkoutSession(
            workoutType: "running",
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 1800),
            durationMinutes: 30,
            totalCalories: 300.5,
            distanceMeters: 5000
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["workoutType"] as? String, "running")
        XCTAssertEqual(json["durationMinutes"] as? Int, 30)
        XCTAssertEqual(json["totalCalories"] as? Double, 300.5)
    }

    func testWorkoutErrorDescriptions() {
        XCTAssertEqual(WorkoutReader.WorkoutError.healthKitNotAvailable.errorDescription,
                       "HealthKit is not available on this device")
        XCTAssertEqual(WorkoutReader.WorkoutError.noData.errorDescription,
                       "No workout data found for the requested period")
    }
}
