import SwiftUI

@main
struct ZaapApp: App {

    @State private var deliveryService = LocationDeliveryService.shared

    init() {
        LocationDeliveryService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(deliveryService.location)
        }
    }
}
