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
        XCTAssertEqual(WorkoutReader.WorkoutError.authorizationDenied.errorDescription,
                       "HealthKit workout data access denied")
        XCTAssertEqual(WorkoutReader.WorkoutError.noData.errorDescription,
                       "No workout data found for the requested period")
    }

    // MARK: - Failure paths (HealthKit unavailable in simulator)

    func testRequestAuthorizationThrowsWhenHealthKitUnavailable() async {
        let reader = WorkoutReader()
        do {
            try await reader.requestAuthorization()
        } catch {
            XCTAssertEqual(error as? WorkoutReader.WorkoutError, .healthKitNotAvailable)
        }
    }

    func testFetchWorkoutsThrowsWhenHealthKitUnavailable() async {
        let reader = WorkoutReader()
        do {
            _ = try await reader.fetchWorkouts()
        } catch {
            XCTAssertEqual(error as? WorkoutReader.WorkoutError, .healthKitNotAvailable)
        }
    }

    func testFetchRecentSessionsThrowsWhenHealthKitUnavailable() async {
        let reader = WorkoutReader()
        do {
            _ = try await reader.fetchRecentSessions(from: nil, to: nil)
        } catch {
            XCTAssertEqual(error as? WorkoutReader.WorkoutError, .healthKitNotAvailable)
        }
    }

    func testWorkoutSessionWithNilOptionals() throws {
        let session = WorkoutReader.WorkoutSession(
            workoutType: "other",
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 1800),
            durationMinutes: 30,
            totalCalories: nil,
            distanceMeters: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["workoutType"] as? String, "other")
        XCTAssertNil(json["totalCalories"])
        XCTAssertNil(json["distanceMeters"])
    }

    func testInitSetsDefaultState() {
        let reader = WorkoutReader()
        XCTAssertFalse(reader.isAuthorized)
        XCTAssertNil(reader.lastError)
    }
}
