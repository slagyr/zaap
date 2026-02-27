import XCTest
import SwiftUI
@testable import Zaap

final class SettingsViewTests: XCTestCase {

    func testSettingsViewIsAView() {
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let view = SettingsView(settings: settings)
        XCTAssertNotNil(view.body)
    }

    func testTokenLabelPropertiesExist() {
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let view = SettingsView(settings: settings)
        XCTAssertEqual(view.hooksTokenLabel, "Hooks Bearer Token")
        XCTAssertEqual(view.gatewayTokenLabel, "Gateway Bearer Token")
    }
}
