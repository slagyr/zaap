import Foundation
import HealthKit
import os

/// Reads sleep analysis data from HealthKit and provides structured summaries.
@Observable
final class SleepDataReader {

    // MARK: - Types

    /// A single sleep session (one continuous period of a given sleep stage).
    struct SleepSession: Codable, Sendable {
        let startDate: Date
        let endDate: Date
        let stage: String        // "inBed", "asleepCore", "asleepDeep", "asleepREM", "asleepUnspecified", "awake"
        let durationMinutes: Int

        var duration: TimeInterval {
            endDate.timeIntervalSince(startDate)
        }
    }

    /// Aggregated summary for a single night's sleep.
    struct SleepSummary: Codable, Sendable {
        let date: String               // YYYY-MM-DD of the night (date you went to bed)
        let bedtime: Date?
        let wakeTime: Date?
        let totalInBedMinutes: Int
        let totalAsleepMinutes: Int
        let deepSleepMinutes: Int
        let remSleepMinutes: Int
        let coreSleepMinutes: Int
        let awakeMinutes: Int
        let sessions: [SleepSession]
    }

    enum SleepError: Error, LocalizedError {
        case healthKitNotAvailable
        case authorizationDenied
        case noData

        var errorDescription: String? {
            switch self {
            case .healthKitNotAvailable: "HealthKit is not available on this device"
            case .authorizationDenied: "HealthKit sleep data access denied"
            case .noData: "No sleep data found for the requested period"
            }
        }
    }

    // MARK: - Properties

    static let shared = SleepDataReader()

    private let healthStore: HKHealthStore?
    private let logger = Logger(subsystem: "com.zaap.app", category: "SleepDataReader")

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

    /// Request read access to sleep analysis data.
    func requestAuthorization() async throws {
        guard let healthStore else {
            throw SleepError.healthKitNotAvailable
        }

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw SleepError.healthKitNotAvailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: [sleepType])
        isAuthorized = true
        logger.info("HealthKit sleep authorization granted")
    }

    // MARK: - Querying

    /// Fetch sleep samples for a date range. Defaults to last night (6 PM yesterday to noon today).
    func fetchSleepSamples(from startDate: Date? = nil, to endDate: Date? = nil) async throws -> [HKCategorySample] {
        guard let healthStore else {
            throw SleepError.healthKitNotAvailable
        }

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw SleepError.healthKitNotAvailable
        }

        let calendar = Calendar.current
        let now = Date()

        // Default window: 6 PM yesterday to noon today — covers a typical night.
        let queryEnd = endDate ?? calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
        let queryStart = startDate ?? calendar.date(byAdding: .hour, value: -18, to: queryEnd) ?? now.addingTimeInterval(-64800)

        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: queryEnd, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let categorySamples = (samples as? [HKCategorySample]) ?? []
                continuation.resume(returning: categorySamples)
            }
            healthStore.execute(query)
        }
    }

    /// Build a sleep summary from raw HealthKit samples for the most recent night.
    func fetchLastNightSummary() async throws -> SleepSummary {
        let samples = try await fetchSleepSamples()

        if samples.isEmpty {
            throw SleepError.noData
        }

        let sessions = samples.map { sample -> SleepSession in
            let stage = Self.stageName(for: sample.value)
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            return SleepSession(
                startDate: sample.startDate,
                endDate: sample.endDate,
                stage: stage,
                durationMinutes: Int(duration / 60)
            )
        }

        let totalInBed = sessions.filter { $0.stage == "inBed" }.reduce(0) { $0 + $1.durationMinutes }
        let deep = sessions.filter { $0.stage == "asleepDeep" }.reduce(0) { $0 + $1.durationMinutes }
        let rem = sessions.filter { $0.stage == "asleepREM" }.reduce(0) { $0 + $1.durationMinutes }
        let core = sessions.filter { $0.stage == "asleepCore" }.reduce(0) { $0 + $1.durationMinutes }
        let unspecified = sessions.filter { $0.stage == "asleepUnspecified" }.reduce(0) { $0 + $1.durationMinutes }
        let awake = sessions.filter { $0.stage == "awake" }.reduce(0) { $0 + $1.durationMinutes }
        let totalAsleep = deep + rem + core + unspecified

        let bedtime = sessions.first?.startDate
        let wakeTime = sessions.last?.endDate

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let nightDate = bedtime.map { dateFormatter.string(from: $0) } ?? dateFormatter.string(from: Date())

        let summary = SleepSummary(
            date: nightDate,
            bedtime: bedtime,
            wakeTime: wakeTime,
            totalInBedMinutes: totalInBed,
            totalAsleepMinutes: totalAsleep,
            deepSleepMinutes: deep,
            remSleepMinutes: rem,
            coreSleepMinutes: core,
            awakeMinutes: awake,
            sessions: sessions
        )

        logger.info("Sleep summary: \(totalAsleep)min asleep, \(deep)min deep, \(rem)min REM")
        return summary
    }

    // MARK: - Helpers

    private static func stageName(for value: Int) -> String {
        guard let sleepValue = HKCategoryValueSleepAnalysis(rawValue: value) else {
            return "unknown"
        }
        switch sleepValue {
        case .inBed: return "inBed"
        case .asleepCore: return "asleepCore"
        case .asleepDeep: return "asleepDeep"
        case .asleepREM: return "asleepREM"
        case .asleepUnspecified: return "asleepUnspecified"
        case .awake: return "awake"
        @unknown default: return "unknown"
        }
    }
}
