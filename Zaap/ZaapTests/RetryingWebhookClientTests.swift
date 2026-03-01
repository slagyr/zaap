import XCTest
@testable import Zaap

final class RetryingWebhookClientTests: XCTestCase {

    // MARK: - Helpers

    private func makeClient(
        webhook: MockWebhookClient? = nil,
        queue: WebhookRetryQueue? = nil,
        poster: MockRawPoster? = nil
    ) -> (RetryingWebhookClient, MockWebhookClient, WebhookRetryQueue, MockRawPoster) {
        let w = webhook ?? MockWebhookClient()
        let q = queue ?? WebhookRetryQueue(skipLoad: true)
        let p = poster ?? MockRawPoster()
        let drain = RetryDrainService(queue: q, poster: p, drainInterval: 0)
        let client = RetryingWebhookClient(inner: w, retryQueue: q, drainService: drain)
        return (client, w, q, p)
    }

    // MARK: - Success path

    func testPostDelegatesToInnerClient() async throws {
        let (client, webhook, _, _) = makeClient()

        try await client.post(["key": "value"], to: "/test")

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/test")
    }

    func testPostForegroundDelegatesToInnerClient() async throws {
        let (client, webhook, _, _) = makeClient()

        try await client.postForeground(["key": "value"], to: "/test")

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/test")
    }

    func testSuccessfulPostTriggersDrain() async throws {
        let (client, _, queue, poster) = makeClient()

        // Pre-load queue with a pending item
        queue.enqueue(path: "/old", payload: Data("old".utf8))

        try await client.post(["key": "value"], to: "/test")

        // Drain should have fired and sent the queued item
        XCTAssertEqual(poster.postCalls.count, 1)
        XCTAssertEqual(poster.postCalls[0].path, "/old")
        XCTAssertTrue(queue.isEmpty)
    }

    // MARK: - Failure path (background post)

    func testFailedBackgroundPostEnqueuesItem() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = NSError(domain: "test", code: -1)
        let (client, _, queue, _) = makeClient(webhook: webhook)

        do {
            try await client.post(["key": "value"], to: "/test")
            XCTFail("Expected error")
        } catch {
            // expected
        }

        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.items[0].path, "/test")
    }

    func testFailedBackgroundPostPreservesPayload() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = NSError(domain: "test", code: -1)
        let (client, _, queue, _) = makeClient(webhook: webhook)

        do {
            try await client.post(["name": "test"], to: "/heartrate")
            XCTFail("Expected error")
        } catch {
            // expected
        }

        XCTAssertEqual(queue.count, 1)
        // Verify the payload can be decoded back
        let decoded = try? JSONDecoder().decode([String: String].self, from: queue.items[0].payload)
        XCTAssertEqual(decoded?["name"], "test")
    }

    // MARK: - Foreground failure does NOT enqueue

    func testFailedForegroundPostDoesNotEnqueue() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = NSError(domain: "test", code: -1)
        let (client, _, queue, _) = makeClient(webhook: webhook)

        do {
            try await client.postForeground(["key": "value"], to: "/test")
            XCTFail("Expected error")
        } catch {
            // expected
        }

        // Foreground (interactive) posts should NOT be queued for retry
        XCTAssertTrue(queue.isEmpty)
    }

    // MARK: - Error propagation

    func testFailedPostStillThrowsError() async {
        let webhook = MockWebhookClient()
        let expectedError = NSError(domain: "test", code: 42)
        webhook.shouldThrow = expectedError
        let (client, _, _, _) = makeClient(webhook: webhook)

        do {
            try await client.post(["key": "value"], to: "/test")
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual((error as NSError).code, 42)
        }
    }
}
