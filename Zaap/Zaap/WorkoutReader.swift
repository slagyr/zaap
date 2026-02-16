import Foundation
import HealthKit
import os

/// Reads workout sessions from HealthKit and provides structured summaries.
@Observable
final class WorkoutReader {

    // MARK: - Types

    /// A single workout session with key metrics.
    struct WorkoutSession: Codable, Sendable {
        let workoutType: String
        let startDate: Date
        let endDate: Date
        let durationMinutes: Int
        let totalCalories: Double?
        let distanceMeters: Double?
    }

    enum WorkoutError: Error, LocalizedError {
        case healthKitNotAvailable
        case authorizationDenied
        case noData

        var errorDescription: String? {
            switch self {
            case .healthKitNotAvailable: "HealthKit is not available on this device"
            case .authorizationDenied: "HealthKit workout data access denied"
            case .noData: "No workout data found for the requested period"
            }
        }
    }

    // MARK: - Properties

    static let shared = WorkoutReader()

    private let healthStore: HKHealthStore?
    private let logger = Logger(subsystem: "com.zaap.app", category: "WorkoutReader")

    private(set) var isAuthorized = false
    private(set) var lastError: String?

    // MARK: - Init

    init() {
        if HKHealthStore.isHealthDataAvailable() {
            self.healthStore = HKHealthStore()
        } else {
            self.healthStore = nil
        }
    }

    // MARK: - Authorization

    /// Request read access to workout data.
    func requestAuthorization() async throws {
        guard let healthStore else {
            throw WorkoutError.healthKitNotAvailable
        }

        let workoutType = HKObjectType.workoutType()

        try await healthStore.requestAuthorization(toShare: [], read: [workoutType])
        isAuthorized = true
        logger.info("HealthKit workout authorization granted")
    }

    // MARK: - Querying

    /// Fetch workouts for a date range. Defaults to the last 24 hours.
    func fetchWorkouts(from startDate: Date? = nil, to endDate: Date? = nil) async throws -> [HKWorkout] {
        guard let healthStore else {
            throw WorkoutError.healthKitNotAvailable
        }

        let now = Date()
        let queryEnd = endDate ?? now
        let queryStart = startDate ?? Calendar.current.date(byAdding: .hour, value: -24, to: now)!

        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: queryEnd, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let workouts = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }
    }

    /// Fetch recent workouts and convert to WorkoutSession structs.
    func fetchRecentSessions(from startDate: Date? = nil, to endDate: Date? = nil) async throws -> [WorkoutSession] {
        let workouts = try await fetchWorkouts(from: startDate, to: endDate)

        if workouts.isEmpty {
            throw WorkoutError.noData
        }

        return workouts.map { workout in
            let duration = workout.endDate.timeIntervalSince(workout.startDate)
            let calories = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie())
            let distance = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: .meter())

            return WorkoutSession(
                workoutType: Self.workoutTypeName(workout.workoutActivityType),
                startDate: workout.startDate,
                endDate: workout.endDate,
                durationMinutes: Int(duration / 60),
                totalCalories: calories,
                distanceMeters: distance
            )
        }
    }

    // MARK: - Helpers

    private static func workoutTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "running"
        case .cycling: return "cycling"
        case .walking: return "walking"
        case .swimming: return "swimming"
        case .hiking: return "hiking"
        case .yoga: return "yoga"
        case .functionalStrengthTraining: return "strengthTraining"
        case .traditionalStrengthTraining: return "strengthTraining"
        case .highIntensityIntervalTraining: return "hiit"
        case .crossTraining: return "crossTraining"
        case .elliptical: return "elliptical"
        case .rowing: return "rowing"
        case .stairClimbing: return "stairClimbing"
        case .pilates: return "pilates"
        case .dance: return "dance"
        case .cooldown: return "cooldown"
        case .coreTraining: return "coreTraining"
        default: return "other"
        }
    }
}
