import SwiftUI

@main
struct ZaapApp: App {

    @State private var locationManager: LocationManager

    init() {
        let service = LocationDeliveryService.shared
        self._locationManager = State(initialValue: (service.location as? LocationManager) ?? LocationManager())
        service.start()
        SleepDeliveryService.shared.start()
        ActivityDeliveryService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(locationManager)
        }
    }
}
