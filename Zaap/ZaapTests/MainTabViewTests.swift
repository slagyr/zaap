import XCTest
import SwiftUI
@testable import Zaap

final class MainTabViewTests: XCTestCase {

    func testMainTabViewIsAView() {
        let view = MainTabView()
        XCTAssertNotNil(view.body)
    }

    func testDefaultTabIsDashboard() {
        let view = MainTabView()
        XCTAssertEqual(view.selectedTab, 0)
    }

    func testAppLaunchPolicySkipsServicesWhenXCTestIsLoaded() {
        XCTAssertFalse(
            AppLaunchPolicy.shouldStartServices(
                environment: [:],
                isXCTestLoaded: true
            )
        )
    }

    func testAppLaunchPolicyAllowsServicesOutsideTests() {
        XCTAssertTrue(
            AppLaunchPolicy.shouldStartServices(
                environment: [:],
                isXCTestLoaded: false
            )
        )
    }

    func testAppLaunchPolicyHonorsExplicitDisableEnvironmentFlag() {
        XCTAssertFalse(
            AppLaunchPolicy.shouldStartServices(
                environment: ["ZAAP_DISABLE_SERVICE_STARTUP": "1"],
                isXCTestLoaded: false
            )
        )
    }
}
