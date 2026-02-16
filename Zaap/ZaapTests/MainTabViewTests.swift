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
}
