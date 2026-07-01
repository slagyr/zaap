import Foundation
import HealthKit
import os

/// Reads Blood Oxygen Saturation (SpO2) data from HealthKit.
@Observable
final class SpO2Reader {

    // MARK: - Types

    struct SpO2Sample: Codable, Sendable {
        let percentage: Double   // 0–100
        let timestamp: Date
    }

    struct DailySpO2Summary: Codable, Sendable {
        let date: String           // YYYY-MM-DD
        let minSpO2: Double
        let maxSpO2: Double
        let avgSpO2: Double
        let sampleCount: Int
        let samples: [SpO2Sample]
    }

    enum SpO2Error: Error, LocalizedError, Equatable {
        case healthKitNotAvailable
        case authorizationDenied
        case noData

        var errorDescription: String? {
            switch self {
            case .healthKitNotAvailable: "HealthKit is not available on this device"
            case .authorizationDenied: "HealthKit SpO2 access denied"
            case .noData: "No SpO2 data found for the requested period"
            }
        }
    }

    // MARK: - Properties

    static let shared = SpO2Reader()

    private let healthStore: HKHealthStore?
    private let logger = Logger(subsystem: "com.zaap.app", category: "SpO2Reader")

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
            throw SpO2Error.healthKitNotAvailable
        }

        guard let spo2Type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else {
            throw SpO2Error.healthKitNotAvailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: [spo2Type])
        isAuthorized = true
        logger.info("HealthKit SpO2 authorization granted")
    }

    // MARK: - Querying

    func fetchSpO2Samples(from startDate: Date? = nil, to endDate: Date? = nil) async throws -> [SpO2Sample] {
        guard let healthStore else {
            throw SpO2Error.healthKitNotAvailable
        }

        guard let spo2Type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else {
            throw SpO2Error.healthKitNotAvailable
        }

        let now = Date()
        let queryEnd = endDate ?? now
        let queryStart = startDate ?? Calendar.current.date(byAdding: .hour, value: -24, to: queryEnd) ?? now.addingTimeInterval(-86400)

        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: queryEnd, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: spo2Type,
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

        let percentUnit = HKUnit.percent()
        return samples.map { sample in
            SpO2Sample(
                percentage: sample.quantity.doubleValue(for: percentUnit) * 100,
                timestamp: sample.startDate
            )
        }
    }

    func fetchDailySummary() async throws -> DailySpO2Summary {
        try await fetchDailySummary(for: Date())
    }

    func fetchDailySummary(for date: Date) async throws -> DailySpO2Summary {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)

        let samples = try await fetchSpO2Samples(from: startOfDay, to: endOfDay)

        guard !samples.isEmpty else {
            throw SpO2Error.noData
        }

        let percentages = samples.map(\.percentage)
        let minSpO2 = percentages.min() ?? 0
        let maxSpO2 = percentages.max() ?? 0
        let avgSpO2 = percentages.reduce(0, +) / Double(percentages.count)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let summary = DailySpO2Summary(
            date: dateFormatter.string(from: date),
            minSpO2: minSpO2,
            maxSpO2: maxSpO2,
            avgSpO2: avgSpO2,
            sampleCount: samples.count,
            samples: samples
        )

        logger.info("SpO2 summary: min=\(minSpO2) max=\(maxSpO2) avg=\(avgSpO2) samples=\(samples.count)")
        return summary
    }
}
