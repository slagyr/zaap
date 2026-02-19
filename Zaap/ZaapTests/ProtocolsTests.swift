import XCTest
@testable import Zaap

final class ProtocolsTests: XCTestCase {

    func testSendNowErrorNotConfiguredDescription() {
        let error = SendNowError.notConfigured
        XCTAssertEqual(error.errorDescription, "Webhook URL and auth token must be configured.")
    }

    func testSendNowErrorNoDataDescription() {
        let error = SendNowError.noData("heart rate")
        XCTAssertEqual(error.errorDescription, "No data available: heart rate")
    }

    func testNullDeliveryLogDoesNotCrash() {
        let log = NullDeliveryLog()
        // Should be a no-op, just verify it doesn't crash
        log.record(dataType: .location, timestamp: Date(), success: true, errorMessage: nil)
        log.record(dataType: .sleep, timestamp: Date(), success: false, errorMessage: "test error")
    }
}
