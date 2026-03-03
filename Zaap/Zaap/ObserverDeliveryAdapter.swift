import Foundation
import os

final class ObserverDeliveryAdapter: ObserverDeliveryDelegate {

    private let logger = Logger(subsystem: "com.zaap.app", category: "ObserverDeliveryAdapter")

    private let heartRateService: HeartRateDeliveryService
    private let sleepService: SleepDeliveryService
    private let activityService: ActivityDeliveryService
    private let workoutService: WorkoutDeliveryService
    private let hrvService: HRVDeliveryService
    private let spo2Service: SpO2DeliveryService
    private let hrvService: HRVDeliveryService

    init(
        heartRateService: HeartRateDeliveryService = .shared,
        sleepService: SleepDeliveryService = .shared,
        activityService: ActivityDeliveryService = .shared,
        workoutService: WorkoutDeliveryService = .shared,
        hrvService: HRVDeliveryService = .shared
    ) {
        self.heartRateService = heartRateService
        self.sleepService = sleepService
        self.activityService = activityService
        self.workoutService = workoutService
        self.hrvService = hrvService
    }

    func deliverData(for dataType: ObservedHealthDataType) async {
        logger.info("Delivering data for observer callback: \(dataType.rawValue)")

        switch dataType {
        case .heartRate:
            await heartRateService.deliverDailySummary()
        case .sleep:
            sleepService.deliverLatest()
        case .activity:
            activityService.deliverLatest()
        case .workout:
            workoutService.deliverLatest()
        case .hrv:
            await hrvService.deliverDailySummary()
        }
    }
}
