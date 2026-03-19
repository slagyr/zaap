import Foundation
import HealthKit
import os

/// Reads Heart Rate Variability (HRV) data from HealthKit — SDNN values and daily summaries.
@Observable
final class HRVReader {

    // MARK: - Types

    struct HRVSample: Codable, Sendable {
        let sdnn: Double      // SDNN in milliseconds
        let timestamp: Date
    }

    struct DailyHRVSummary: Codable, Sendable {
        let date: String           // YYYY-MM-DD
        let minSDNN: Double
        let maxSDNN: Double
        let avgSDNN: Double
        let sampleCount: Int
        let samples: [HRVSample]
    }

    enum HRVError: Error, LocalizedError, Equatable {
        case healthKitNotAvailable
        case authorizationDenied
        case noData

        var errorDescription: String? {
            switch self {
            case .healthKitNotAvailable: "HealthKit is not available on this device"
            case .authorizationDenied: "HealthKit HRV access denied"
            case .noData: "No HRV data found for the requested period"
            }
        }
    }

    // MARK: - Properties

    static let shared = HRVReader()

    private let healthStore: HKHealthStore?
    private let logger = Logger(subsystem: "com.zaap.app", category: "HRVReader")

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
            throw HRVError.healthKitNotAvailable
        }

        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HRVError.healthKitNotAvailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: [hrvType])
        isAuthorized = true
        logger.info("HealthKit HRV authorization granted")
    }

    // MARK: - Querying

    func fetchHRVSamples(from startDate: Date? = nil, to endDate: Date? = nil) async throws -> [HRVSample] {
        guard let healthStore else {
            throw HRVError.healthKitNotAvailable
        }

        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HRVError.healthKitNotAvailable
        }

        let now = Date()
        let queryEnd = endDate ?? now
        let queryStart = startDate ?? Calendar.current.date(byAdding: .hour, value: -24, to: queryEnd) ?? now.addingTimeInterval(-86400)

        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: queryEnd, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
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

        let msUnit = HKUnit.secondUnit(with: .milli)
        return samples.map { sample in
            HRVSample(
                sdnn: sample.quantity.doubleValue(for: msUnit),
                timestamp: sample.startDate
            )
        }
    }

    func fetchDailySummary() async throws -> DailyHRVSummary {
        try await fetchDailySummary(for: Date())
    }

    func fetchDailySummary(for date: Date) async throws -> DailyHRVSummary {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)

        let samples = try await fetchHRVSamples(from: startOfDay, to: endOfDay)

        guard !samples.isEmpty else {
            throw HRVError.noData
        }

        let sdnns = samples.map(\.sdnn)
        let minSDNN = sdnns.min() ?? 0
        let maxSDNN = sdnns.max() ?? 0
        let avgSDNN = sdnns.reduce(0, +) / Double(sdnns.count)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let summary = DailyHRVSummary(
            date: dateFormatter.string(from: date),
            queryTimestamp: Date(),
            minSDNN: minSDNN,
            maxSDNN: maxSDNN,
            avgSDNN: avgSDNN,
            sampleCount: samples.count,
            samples: samples
        )

        logger.info("HRV summary: min=\(minSDNN) max=\(maxSDNN) avg=\(avgSDNN) samples=\(samples.count)")
        return summary
    }
}
