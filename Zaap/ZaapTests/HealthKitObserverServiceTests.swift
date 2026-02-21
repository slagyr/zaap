import XCTest
@testable import Zaap

final class HealthKitObserverServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService(
        settings: SettingsManager? = nil
    ) -> (HealthKitObserverService, MockHealthKitObserverBackend, MockObserverDeliveryDelegate, SettingsManager) {
        let s = settings ?? SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let backend = MockHealthKitObserverBackend()
        let delegate = MockObserverDeliveryDelegate()
        let service = HealthKitObserverService(backend: backend, deliveryDelegate: delegate, settings: s)
        return (service, backend, delegate, s)
    }

    // MARK: - start()

    func testStartDoesNothingWhenNotConfigured() {
        let (service, backend, _, settings) = makeService()
        // Not configured — no webhookURL or authToken
        service.start()
        XCTAssertEqual(backend.enableBackgroundDeliveryCalls.count, 0)
        XCTAssertEqual(backend.observerQueryCalls.count, 0)
    }

    func testStartRegistersObserversForAllEnabledTypes() {
        let (service, backend, _, settings) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.heartRateTrackingEnabled = true
        settings.sleepTrackingEnabled = true
        settings.activityTrackingEnabled = true
        settings.workoutTrackingEnabled = true

        service.start()

        // Should register background delivery for 4 types
        XCTAssertEqual(backend.enableBackgroundDeliveryCalls.count, 4)
        // Should create observer queries for 4 types
        XCTAssertEqual(backend.observerQueryCalls.count, 4)
    }

    func testStartOnlyRegistersEnabledTypes() {
        let (service, backend, _, settings) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.heartRateTrackingEnabled = true
        settings.sleepTrackingEnabled = false
        settings.activityTrackingEnabled = false
        settings.workoutTrackingEnabled = false

        service.start()

        XCTAssertEqual(backend.enableBackgroundDeliveryCalls.count, 1)
        XCTAssertEqual(backend.observerQueryCalls.count, 1)
        XCTAssertEqual(backend.enableBackgroundDeliveryCalls[0].dataType, .heartRate)
    }

    func testStartUsesCorrectFrequencies() {
        let (service, backend, _, settings) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.heartRateTrackingEnabled = true
        settings.sleepTrackingEnabled = true
        settings.activityTrackingEnabled = true
        settings.workoutTrackingEnabled = true

        service.start()

        let freqByType = Dictionary(
            backend.enableBackgroundDeliveryCalls.map { ($0.dataType, $0.frequency) },
            uniquingKeysWith: { _, last in last }
        )

        XCTAssertEqual(freqByType[.heartRate], .immediate)
        XCTAssertEqual(freqByType[.workout], .immediate)
        XCTAssertEqual(freqByType[.sleep], .immediate)
        XCTAssertEqual(freqByType[.activity], .hourly)
    }

    // MARK: - Observer callback triggers delivery

    func testObserverCallbackTriggersDeliveryDelegate() async {
        let (service, backend, delegate, settings) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.heartRateTrackingEnabled = true

        service.start()

        // Simulate HealthKit firing the observer query
        XCTAssertEqual(backend.observerQueryCalls.count, 1)
        let call = backend.observerQueryCalls[0]
        XCTAssertEqual(call.dataType, .heartRate)

        // Fire the callback
        let expectation = expectation(description: "completion handler called")
        call.handler {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2.0)

        // Delegate should have been asked to deliver heart rate data
        XCTAssertEqual(delegate.deliverCalls.count, 1)
        XCTAssertEqual(delegate.deliverCalls[0], .heartRate)
    }

    func testObserverCallbackCallsCompletionHandler() async {
        let (service, backend, delegate, settings) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.sleepTrackingEnabled = true

        service.start()

        let call = backend.observerQueryCalls[0]
        var completionCalled = false

        let expectation = expectation(description: "completion called")
        call.handler {
            completionCalled = true
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertTrue(completionCalled, "Must call completion handler so iOS doesn't throttle future wakes")
    }

    // MARK: - stop()

    func testStopRemovesAllObservers() {
        let (service, backend, _, settings) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.heartRateTrackingEnabled = true
        settings.sleepTrackingEnabled = true

        service.start()
        XCTAssertEqual(backend.observerQueryCalls.count, 2)

        service.stop()
        XCTAssertEqual(backend.stopQueryCalls, 2)
    }

    // MARK: - Idempotency

    func testStartIsIdempotent() {
        let (service, backend, _, settings) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.heartRateTrackingEnabled = true

        service.start()
        service.start() // second call should stop old observers first

        // Should have stopped the first observer and created a new one
        XCTAssertEqual(backend.stopQueryCalls, 1)
        XCTAssertEqual(backend.observerQueryCalls.count, 2)
    }
}

// MARK: - Test Doubles

final class MockHealthKitObserverBackend: HealthKitObserverBackend {
    struct EnableBGCall {
        let dataType: ObservedHealthDataType
        let frequency: ObserverFrequency
    }

    struct ObserverQueryCall {
        let dataType: ObservedHealthDataType
        let handler: (@escaping () -> Void) -> Void
    }

    var enableBackgroundDeliveryCalls: [EnableBGCall] = []
    var observerQueryCalls: [ObserverQueryCall] = []
    var stopQueryCalls = 0

    func enableBackgroundDelivery(for dataType: ObservedHealthDataType, frequency: ObserverFrequency, completion: @escaping (Bool, Error?) -> Void) {
        enableBackgroundDeliveryCalls.append(EnableBGCall(dataType: dataType, frequency: frequency))
        completion(true, nil)
    }

    func startObserverQuery(for dataType: ObservedHealthDataType, handler: @escaping (@escaping () -> Void) -> Void) -> Any {
        let call = ObserverQueryCall(dataType: dataType, handler: handler)
        observerQueryCalls.append(call)
        return "query-\(dataType)" as AnyObject
    }

    func stopQuery(_ query: Any) {
        stopQueryCalls += 1
    }
}

final class MockObserverDeliveryDelegate: ObserverDeliveryDelegate {
    var deliverCalls: [ObservedHealthDataType] = []

    func deliverData(for dataType: ObservedHealthDataType) async {
        deliverCalls.append(dataType)
    }
}
