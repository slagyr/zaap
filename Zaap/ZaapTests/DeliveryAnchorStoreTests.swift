import XCTest
@testable import Zaap

final class DeliveryAnchorStoreTests: XCTestCase {

    private func makeStore() -> UserDefaultsDeliveryAnchorStore {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return UserDefaultsDeliveryAnchorStore(defaults: defaults)
    }

    func testReturnsNilWhenNoAnchorSet() {
        let store = makeStore()
        XCTAssertNil(store.lastDelivered(for: .heartRate))
    }

    func testStoresAndRetrievesAnchor() {
        let store = makeStore()
        let now = Date()
        store.setLastDelivered(now, for: .heartRate)
        let retrieved = store.lastDelivered(for: .heartRate)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved!.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
    }

    func testAnchorsArePerDataType() {
        let store = makeStore()
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        store.setLastDelivered(date1, for: .heartRate)
        store.setLastDelivered(date2, for: .sleep)
        XCTAssertEqual(store.lastDelivered(for: .heartRate)!.timeIntervalSince1970, 1000, accuracy: 0.001)
        XCTAssertEqual(store.lastDelivered(for: .sleep)!.timeIntervalSince1970, 2000, accuracy: 0.001)
        XCTAssertNil(store.lastDelivered(for: .activity))
    }

    func testNullStoreAlwaysReturnsNil() {
        let store = NullDeliveryAnchorStore()
        store.setLastDelivered(Date(), for: .heartRate)
        XCTAssertNil(store.lastDelivered(for: .heartRate))
    }
}
