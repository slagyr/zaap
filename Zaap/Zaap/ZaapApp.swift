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
        LocationDeliveryService.shared.start()
        SleepDeliveryService.shared.start()
        ActivityDeliveryService.shared.start()
    }
}
