import Foundation
import HealthKit
import os

/// Reads Respiratory Rate data from HealthKit — breaths per minute values and daily summaries.
@Observable
final class RespiratoryRateReader {

    // MARK: - Types

    struct RespiratoryRateSample: Codable, Sendable {
        let breathsPerMinute: Double
        let timestamp: Date
    }

    struct DailyRespiratoryRateSummary: Codable, Sendable {
        let date: String           // YYYY-MM-DD
        let minRate: Double
        let maxRate: Double
        let avgRate: Double
        let sampleCount: Int
        let samples: [RespiratoryRateSample]

        enum CodingKeys: String, CodingKey {
            case date
            case minRate = "min"
            case maxRate = "max"
            case avgRate = "avg"
            case sampleCount
            case samples
        }
    }

    enum RespiratoryRateError: Error, LocalizedError, Equatable {
        case healthKitNotAvailable
        case authorizationDenied
        case noData

        var errorDescription: String? {
            switch self {
            case .healthKitNotAvailable: "HealthKit is not available on this device"
            case .authorizationDenied: "HealthKit respiratory rate access denied"
            case .noData: "No respiratory rate data found for the requested period"
            }
        }
    }

    // MARK: - Properties

    static let shared = RespiratoryRateReader()

    private let healthStore: HKHealthStore?
    private let logger = Logger(subsystem: "com.zaap.app", category: "RespiratoryRateReader")

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
            throw RespiratoryRateError.healthKitNotAvailable
        }

        guard let rrType = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else {
            throw RespiratoryRateError.healthKitNotAvailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: [rrType])
        isAuthorized = true
        logger.info("HealthKit respiratory rate authorization granted")
    }

    // MARK: - Querying

    func fetchSamples(from startDate: Date? = nil, to endDate: Date? = nil) async throws -> [RespiratoryRateSample] {
        guard let healthStore else {
            throw RespiratoryRateError.healthKitNotAvailable
        }

        guard let rrType = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else {
            throw RespiratoryRateError.healthKitNotAvailable
        }

        let now = Date()
        let queryEnd = endDate ?? now
        let queryStart = startDate ?? Calendar.current.date(byAdding: .hour, value: -24, to: queryEnd) ?? now.addingTimeInterval(-86400)

        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: queryEnd, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: rrType,
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
            RespiratoryRateSample(
                breathsPerMinute: sample.quantity.doubleValue(for: bpmUnit),
                timestamp: sample.startDate
            )
        }
    }

    func fetchDailySummary() async throws -> DailyRespiratoryRateSummary {
        try await fetchDailySummary(for: Date())
    }

    func fetchDailySummary(for date: Date) async throws -> DailyRespiratoryRateSummary {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)

        let samples = try await fetchSamples(from: startOfDay, to: endOfDay)

        guard !samples.isEmpty else {
            throw RespiratoryRateError.noData
        }

        let rates = samples.map(\.breathsPerMinute)
        let minRate = rates.min() ?? 0
        let maxRate = rates.max() ?? 0
        let avgRate = rates.reduce(0, +) / Double(rates.count)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let summary = DailyRespiratoryRateSummary(
            date: dateFormatter.string(from: date),
            queryTimestamp: Date(),
            minRate: minRate,
            maxRate: maxRate,
            avgRate: avgRate,
            sampleCount: samples.count,
            samples: samples
        )

        logger.info("Respiratory rate summary: min=\(minRate) max=\(maxRate) avg=\(avgRate) samples=\(samples.count)")
        return summary
    }
}
