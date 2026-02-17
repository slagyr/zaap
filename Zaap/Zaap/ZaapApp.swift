import SwiftUI
import SwiftData

@main
struct ZaapApp: App {

    @State private var locationManager: LocationManager

    init() {
        // Safe initialization — never crash on launch
        let manager: LocationManager
        if let lm = LocationDeliveryService.shared.location as? LocationManager {
            manager = lm
        } else {
            manager = LocationManager()
        }
        self._locationManager = State(initialValue: manager)
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(locationManager)
                .modelContainer(for: DeliveryRecord.self)
                .task {
                    // Deferred start — runs after UI is up, won't crash launch
                    LocationDeliveryService.shared.start()
                    SleepDeliveryService.shared.start()
                    ActivityDeliveryService.shared.start()
                }
        }
    }
}
