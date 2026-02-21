import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.zaap.app", category: "AppLaunch")

@main
struct ZaapApp: App {

    let modelContainer: ModelContainer?

    init() {
        // SwiftData container — can fail on device if schema migration breaks
        do {
            modelContainer = try ModelContainer(for: DeliveryRecord.self)
            logger.info("ModelContainer initialized")
        } catch {
            logger.error("ModelContainer failed: \(error.localizedDescription, privacy: .public)")
            modelContainer = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                MainTabView()
                    .modelContainer(modelContainer)
                    .task {
                        startServices()
                    }
            } else {
                // Fallback UI if SwiftData fails — app still launches
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("Database Error")
                        .font(.headline)
                    Text("Please delete and reinstall the app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
    }

    private func startServices() {
        logger.info("Starting delivery services")
        guard let context = modelContainer?.mainContext else {
            logger.error("Cannot start services — no model context")
            return
        }
        let deliveryLog = DeliveryLogService(context: context)
        LocationDeliveryService.shared.configure(deliveryLog: deliveryLog)
        SleepDeliveryService.shared.configure(deliveryLog: deliveryLog)
        HeartRateDeliveryService.shared.configure(deliveryLog: deliveryLog)
        ActivityDeliveryService.shared.configure(deliveryLog: deliveryLog)
        WorkoutDeliveryService.shared.configure(deliveryLog: deliveryLog)
        LocationDeliveryService.shared.start()
        SleepDeliveryService.shared.start()
        HeartRateDeliveryService.shared.start()
        ActivityDeliveryService.shared.start()
        WorkoutDeliveryService.shared.start()

        // Start HealthKit observer queries for background delivery
        let deliveryAdapter = ObserverDeliveryAdapter()
        HealthKitObserverService.shared.configure(deliveryDelegate: deliveryAdapter)
        HealthKitObserverService.shared.start()
    }
}
