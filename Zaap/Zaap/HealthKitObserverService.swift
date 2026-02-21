import Foundation
import HealthKit
import os

/// The types of health data that can be observed for background delivery.
enum ObservedHealthDataType: String, CaseIterable {
    case heartRate
    case sleep
    case activity
    case workout
}

/// Background delivery frequency for observer queries.
enum ObserverFrequency {
    case immediate
    case hourly

    var hkFrequency: HKUpdateFrequency {
        switch self {
        case .immediate: return .immediate
        case .hourly: return .hourly
        }
    }
}

/// Abstraction over HKHealthStore for observer query operations.
/// Allows testing without a real HealthKit store.
protocol HealthKitObserverBackend {
    func enableBackgroundDelivery(for dataType: ObservedHealthDataType, frequency: ObserverFrequency, completion: @escaping (Bool, Error?) -> Void)
    func startObserverQuery(for dataType: ObservedHealthDataType, handler: @escaping (@escaping () -> Void) -> Void) -> Any
    func stopQuery(_ query: Any)
}

/// Delegate that performs the actual data fetch + delivery when an observer fires.
protocol ObserverDeliveryDelegate: AnyObject {
    func deliverData(for dataType: ObservedHealthDataType) async
}

/// Manages HKObserverQuery + enableBackgroundDelivery for all HealthKit types.
/// When the Apple Watch or any app writes new data, iOS wakes Zaap and it fetches+delivers immediately.
final class HealthKitObserverService {

    static let shared = HealthKitObserverService()

    private let logger = Logger(subsystem: "com.zaap.app", category: "HealthKitObserver")

    private let backend: HealthKitObserverBackend
    private weak var deliveryDelegate: ObserverDeliveryDelegate?
    private let settings: SettingsManager
    private var activeQueries: [ObservedHealthDataType: Any] = [:]

    init(
        backend: HealthKitObserverBackend = HKObserverBackend(),
        deliveryDelegate: ObserverDeliveryDelegate? = nil,
        settings: SettingsManager = .shared
    ) {
        self.backend = backend
        self.deliveryDelegate = deliveryDelegate
        self.settings = settings
    }

    /// Set the delivery delegate (called from ZaapApp after services are configured).
    func configure(deliveryDelegate: ObserverDeliveryDelegate) {
        self.deliveryDelegate = deliveryDelegate
    }

    // MARK: - Frequency mapping

    private func frequency(for dataType: ObservedHealthDataType) -> ObserverFrequency {
        switch dataType {
        case .heartRate: return .immediate
        case .workout: return .immediate
        case .sleep: return .immediate
        case .activity: return .hourly
        }
    }

    // MARK: - Enabled types

    private func enabledTypes() -> [ObservedHealthDataType] {
        var types: [ObservedHealthDataType] = []
        if settings.heartRateTrackingEnabled { types.append(.heartRate) }
        if settings.sleepTrackingEnabled { types.append(.sleep) }
        if settings.activityTrackingEnabled { types.append(.activity) }
        if settings.workoutTrackingEnabled { types.append(.workout) }
        return types
    }

    // MARK: - Public

    /// Register observer queries and enable background delivery for all enabled HealthKit types.
    func start() {
        guard settings.isConfigured else {
            logger.info("Observer service not started — not configured")
            return
        }

        // Stop existing observers first (idempotency)
        if !activeQueries.isEmpty {
            stop()
        }

        let types = enabledTypes()
        guard !types.isEmpty else {
            logger.info("Observer service not started — no tracking types enabled")
            return
        }

        for dataType in types {
            let freq = frequency(for: dataType)

            // Enable background delivery
            backend.enableBackgroundDelivery(for: dataType, frequency: freq) { [logger] success, error in
                if let error {
                    logger.error("enableBackgroundDelivery failed for \(dataType.rawValue): \(error.localizedDescription, privacy: .public)")
                } else {
                    logger.info("Background delivery enabled for \(dataType.rawValue) (\(String(describing: freq)))")
                }
            }

            // Start observer query
            let query = backend.startObserverQuery(for: dataType) { [weak self] completionHandler in
                guard let self else {
                    completionHandler()
                    return
                }
                self.logger.info("Observer fired for \(dataType.rawValue)")

                Task {
                    await self.deliveryDelegate?.deliverData(for: dataType)
                    completionHandler()
                }
            }

            activeQueries[dataType] = query
        }

        logger.info("Observer service started with \(types.count) type(s)")
    }

    /// Stop all active observer queries.
    func stop() {
        for (_, query) in activeQueries {
            backend.stopQuery(query)
        }
        activeQueries.removeAll()
        logger.info("Observer service stopped")
    }
}

// MARK: - Real HealthKit Backend

/// Production implementation that wraps HKHealthStore.
final class HKObserverBackend: HealthKitObserverBackend {

    private let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "com.zaap.app", category: "HKObserverBackend")

    private func sampleType(for dataType: ObservedHealthDataType) -> HKSampleType? {
        switch dataType {
        case .heartRate:
            return HKQuantityType.quantityType(forIdentifier: .heartRate)
        case .sleep:
            return HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)
        case .activity:
            return HKQuantityType.quantityType(forIdentifier: .stepCount)
        case .workout:
            return HKWorkoutType.workoutType()
        }
    }

    func enableBackgroundDelivery(for dataType: ObservedHealthDataType, frequency: ObserverFrequency, completion: @escaping (Bool, Error?) -> Void) {
        guard let type = sampleType(for: dataType) else {
            completion(false, nil)
            return
        }
        healthStore.enableBackgroundDelivery(for: type, frequency: frequency.hkFrequency, withCompletion: completion)
    }

    func startObserverQuery(for dataType: ObservedHealthDataType, handler: @escaping (@escaping () -> Void) -> Void) -> Any {
        guard let type = sampleType(for: dataType) else {
            return NSObject() // placeholder — shouldn't happen
        }

        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
            if let error {
                Logger(subsystem: "com.zaap.app", category: "HKObserverBackend")
                    .error("Observer query error for \(dataType.rawValue): \(error.localizedDescription, privacy: .public)")
                completionHandler()
                return
            }
            handler(completionHandler)
        }

        healthStore.execute(query)
        return query
    }

    func stopQuery(_ query: Any) {
        if let hkQuery = query as? HKQuery {
            healthStore.stop(hkQuery)
        }
    }
}
