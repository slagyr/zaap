import Foundation
import HealthKit
import os

/// Reads heart rate data from HealthKit — resting HR, recent samples, and daily min/max/avg.
@Observable
final class HeartRateReader {

    // MARK: - Types

    struct HeartRateSample: Codable, Sendable {
        let bpm: Double
        let timestamp: Date
    }

    struct DailyHeartRateSummary: Codable, Sendable {
        let date: String           // YYYY-MM-DD
        let minBPM: Double
        let maxBPM: Double
        let avgBPM: Double
        let restingBPM: Double?
        let sampleCount: Int
        let samples: [HeartRateSample]
    }

    enum HeartRateError: Error, LocalizedError {
        case healthKitNotAvailable
        case authorizationDenied
        case noData

        var errorDescription: String? {
            switch self {
            case .healthKitNotAvailable: "HealthKit is not available on this device"
            case .authorizationDenied: "HealthKit heart rate access denied"
            case .noData: "No heart rate data found for the requested period"
            }
        }
    }

    // MARK: - Properties

    static let shared = HeartRateReader()

    private let healthStore: HKHealthStore?
    private let logger = Logger(subsystem: "com.zaap.app", category: "HeartRateReader")

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

    /// Request read access to heart rate and resting heart rate data.
    func requestAuthorization() async throws {
        guard let healthStore else {
            throw HeartRateError.healthKitNotAvailable
        }

        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!

        try await healthStore.requestAuthorization(toShare: [], read: [heartRateType, restingHRType])
        isAuthorized = true
        logger.info("HealthKit heart rate authorization granted")
    }

    // MARK: - Querying

    /// Fetch heart rate samples for a date range. Defaults to the last 24 hours.
    func fetchHeartRateSamples(from startDate: Date? = nil, to endDate: Date? = nil) async throws -> [HeartRateSample] {
        guard let healthStore else {
            throw HeartRateError.healthKitNotAvailable
        }

        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let now = Date()
        let queryEnd = endDate ?? now
        let queryStart = startDate ?? Calendar.current.date(byAdding: .hour, value: -24, to: queryEnd)!

        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: queryEnd, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
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
            HeartRateSample(
                bpm: sample.quantity.doubleValue(for: bpmUnit),
                timestamp: sample.startDate
            )
        }
    }

    /// Fetch today's resting heart rate.
    func fetchRestingHeartRate() async throws -> Double? {
        guard let healthStore else {
            throw HeartRateError.healthKitNotAvailable
        }

        let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: restingHRType,
                predicate: predicate,
                limit: 1,
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

        guard let latest = samples.first else { return nil }
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        return latest.quantity.doubleValue(for: bpmUnit)
    }

    /// Build a daily summary with min/max/avg, resting HR, and all samples.
    func fetchDailySummary(for date: Date = Date()) async throws -> DailyHeartRateSummary {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let samples = try await fetchHeartRateSamples(from: startOfDay, to: endOfDay)

        guard !samples.isEmpty else {
            throw HeartRateError.noData
        }

        let bpms = samples.map(\.bpm)
        let minBPM = bpms.min()!
        let maxBPM = bpms.max()!
        let avgBPM = bpms.reduce(0, +) / Double(bpms.count)

        let restingBPM = try? await fetchRestingHeartRate()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let summary = DailyHeartRateSummary(
            date: dateFormatter.string(from: date),
            minBPM: minBPM,
            maxBPM: maxBPM,
            avgBPM: avgBPM,
            restingBPM: restingBPM,
            sampleCount: samples.count,
            samples: samples
        )

        logger.info("HR summary: min=\(minBPM) max=\(maxBPM) avg=\(avgBPM) resting=\(restingBPM ?? -1) samples=\(samples.count)")
        return summary
    }
}
