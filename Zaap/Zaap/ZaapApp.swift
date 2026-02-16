import SwiftUI

@main
struct ZaapApp: App {

    @State private var locationManager = LocationDeliveryService.shared.location as! LocationManager

    init() {
        LocationDeliveryService.shared.start()
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
