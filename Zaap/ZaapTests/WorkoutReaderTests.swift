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
                       "No workouts found in the last 24 hours")
    }

    // MARK: - Failure paths (HealthKit unavailable in simulator)

    func testRequestAuthorizationThrowsWhenHealthKitUnavailable() async {
        // Inject a nil healthStore to exercise the guard path explicitly.
        // The simulator's HKHealthStore.isHealthDataAvailable() returns true,
        // so a plain `WorkoutReader()` would skip the guard and call into
        // HKHealthStore.requestAuthorization, which pops a system permission
        // prompt and waits forever for user interaction.
        let reader = WorkoutReader(healthStore: nil)
        do {
            try await reader.requestAuthorization()
            XCTFail("Expected healthKitNotAvailable error")
        } catch {
            XCTAssertEqual(error as? WorkoutReader.WorkoutError, .healthKitNotAvailable)
        }
    }

    func testFetchWorkoutsThrowsWhenHealthStoreUnavailable() async {
        let reader = WorkoutReader(healthStore: nil)
        do {
            _ = try await reader.fetchWorkouts()
            XCTFail("Expected healthKitNotAvailable error")
        } catch {
            XCTAssertEqual(error as? WorkoutReader.WorkoutError, .healthKitNotAvailable)
        }
    }

    func testFetchRecentSessionsThrowsWhenHealthStoreUnavailable() async {
        let reader = WorkoutReader(healthStore: nil)
        do {
            _ = try await reader.fetchRecentSessions(from: nil, to: nil)
            XCTFail("Expected healthKitNotAvailable error")
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

    // MARK: - Mock reader failure paths

    func testMockReaderThrowsAuthorizationDeniedOnFetch() async {
        let reader = MockWorkoutReader()
        reader.shouldThrow = WorkoutReader.WorkoutError.authorizationDenied
        do {
            _ = try await reader.fetchRecentSessions(from: nil, to: nil)
            XCTFail("Expected authorizationDenied error")
        } catch {
            XCTAssertEqual(error as? WorkoutReader.WorkoutError, .authorizationDenied)
        }
    }

    func testMockReaderThrowsAuthorizationDeniedOnRequestAuthorization() async {
        let reader = MockWorkoutReader()
        reader.shouldThrow = WorkoutReader.WorkoutError.authorizationDenied
        do {
            try await reader.requestAuthorization()
            XCTFail("Expected authorizationDenied error")
        } catch {
            XCTAssertEqual(error as? WorkoutReader.WorkoutError, .authorizationDenied)
        }
    }

    func testMockReaderThrowsNoDataWhenShouldThrowSet() async {
        let reader = MockWorkoutReader()
        reader.shouldThrow = WorkoutReader.WorkoutError.noData
        do {
            _ = try await reader.fetchRecentSessions(from: nil, to: nil)
            XCTFail("Expected noData error")
        } catch {
            XCTAssertEqual(error as? WorkoutReader.WorkoutError, .noData)
        }
    }

    func testMockReaderPropagatesNetworkStyleError() async {
        let reader = MockWorkoutReader()
        reader.shouldThrow = URLError(.notConnectedToInternet)
        do {
            _ = try await reader.fetchRecentSessions(from: nil, to: nil)
            XCTFail("Expected URLError")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func testMockReaderReturnsSessionsWhenSet() async throws {
        let reader = MockWorkoutReader()
        reader.sessionsToReturn = [
            WorkoutReader.WorkoutSession(
                workoutType: "running", startDate: Date(timeIntervalSince1970: 0),
                endDate: Date(timeIntervalSince1970: 1800),
                durationMinutes: 30, totalCalories: 300, distanceMeters: 5000
            )
        ]
        let sessions = try await reader.fetchRecentSessions(from: nil, to: nil)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].workoutType, "running")
    }

    func testMockReaderReturnsEmptyArrayByDefault() async throws {
        let reader = MockWorkoutReader()
        let sessions = try await reader.fetchRecentSessions(from: nil, to: nil)
        XCTAssertTrue(sessions.isEmpty)
    }
}
