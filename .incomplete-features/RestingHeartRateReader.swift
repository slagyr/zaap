import Foundation
import HealthKit
import os

/// Reads resting heart rate data from HealthKit — daily summaries of Apple's computed resting HR.
@Observable
final class RestingHeartRateReader {

    // MARK: - Types

    struct RestingHRSample: Codable, Sendable {
        let bpm: Double
        let timestamp: Date
    }

    struct DailyRestingHRSummary: Codable, Sendable {
        let date: String           // YYYY-MM-DD
        let restingBPM: Double
        let sampleCount: Int
        let samples: [RestingHRSample]
    }

    enum RestingHRError: Error, LocalizedError, Equatable {
        case healthKitNotAvailable
        case authorizationDenied
        case noData

        var errorDescription: String? {
            switch self {
            case .healthKitNotAvailable: "HealthKit is not available on this device"
            case .authorizationDenied: "HealthKit resting heart rate access denied"
            case .noData: "No resting heart rate data found for the requested period"
            }
        }
    }

    // MARK: - Properties

    static let shared = RestingHeartRateReader()

    private let healthStore: HKHealthStore?
    private let logger = Logger(subsystem: "com.zaap.app", category: "RestingHeartRateReader")

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

    func requestAuthorization() async throws {
        guard let healthStore else {
            throw RestingHRError.healthKitNotAvailable
        }

        guard let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            throw RestingHRError.healthKitNotAvailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: [restingHRType])
        isAuthorized = true
        logger.info("HealthKit resting heart rate authorization granted")
    }

    // MARK: - Querying

    func fetchSamples(from startDate: Date? = nil, to endDate: Date? = nil) async throws -> [RestingHRSample] {
        guard let healthStore else {
            throw RestingHRError.healthKitNotAvailable
        }

        guard let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            throw RestingHRError.healthKitNotAvailable
        }

        let now = Date()
        let queryEnd = endDate ?? now
        let queryStart = startDate ?? Calendar.current.date(byAdding: .hour, value: -24, to: queryEnd) ?? now.addingTimeInterval(-86400)

        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: queryEnd, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: restingHRType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        return samples.map { sample in
            RestingHRSample(
                bpm: sample.quantity.doubleValue(for: bpmUnit),
                timestamp: sample.startDate
            )
        }
    }

    func fetchDailySummary() async throws -> DailyRestingHRSummary {
        try await fetchDailySummary(for: Date())
    }

    func fetchDailySummary(for date: Date) async throws -> DailyRestingHRSummary {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)

        let samples = try await fetchSamples(from: startOfDay, to: endOfDay)

        guard !samples.isEmpty else {
            throw RestingHRError.noData
        }

        // Resting HR typically has one sample per day; use the most recent value as the primary
        let latestBPM = samples.last!.bpm

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let summary = DailyRestingHRSummary(
            date: dateFormatter.string(from: date),
            restingBPM: latestBPM,
            sampleCount: samples.count,
            samples: samples
        )

        logger.info("Resting HR summary: \(latestBPM) BPM, \(samples.count) sample(s)")
        return summary
    }
}
