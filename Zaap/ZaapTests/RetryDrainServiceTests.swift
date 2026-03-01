import XCTest
@testable import Zaap

final class RetryDrainServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService(
        queue: WebhookRetryQueue? = nil,
        poster: MockRawPoster? = nil
    ) -> (RetryDrainService, WebhookRetryQueue, MockRawPoster) {
        let q = queue ?? WebhookRetryQueue(skipLoad: true)
        let p = poster ?? MockRawPoster()
        let service = RetryDrainService(queue: q, poster: p, drainInterval: 0)
        return (service, q, p)
    }

    // MARK: - notifySuccess triggers drain

    func testNotifySuccessDrainsOneItem() async {
        let (service, queue, poster) = makeService()
        queue.enqueue(path: "/location", payload: Data("1".utf8))

        await service.notifySuccess()

        XCTAssertEqual(poster.postCalls.count, 1)
        XCTAssertEqual(poster.postCalls[0].path, "/location")
        XCTAssertTrue(queue.isEmpty)
    }

    func testNotifySuccessDrainsAllItemsInOrder() async {
        let (service, queue, poster) = makeService()
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)
        let t3 = Date(timeIntervalSince1970: 3000)

        queue.enqueue(path: "/a", payload: Data("1".utf8), originalTimestamp: t1)
        queue.enqueue(path: "/b", payload: Data("2".utf8), originalTimestamp: t2)
        queue.enqueue(path: "/c", payload: Data("3".utf8), originalTimestamp: t3)

        await service.notifySuccess()

        XCTAssertEqual(poster.postCalls.count, 3)
        XCTAssertEqual(poster.postCalls[0].path, "/a")
        XCTAssertEqual(poster.postCalls[1].path, "/b")
        XCTAssertEqual(poster.postCalls[2].path, "/c")
        XCTAssertTrue(queue.isEmpty)
    }

    func testNotifySuccessDoesNothingWhenQueueEmpty() async {
        let (service, _, poster) = makeService()

        await service.notifySuccess()

        XCTAssertEqual(poster.postCalls.count, 0)
    }

    // MARK: - Drain stops on failure

    func testDrainStopsWhenItemFails() async {
        let (service, queue, poster) = makeService()

        queue.enqueue(path: "/a", payload: Data("1".utf8))
        queue.enqueue(path: "/b", payload: Data("2".utf8))
        queue.enqueue(path: "/c", payload: Data("3".utf8))

        poster.failOnCallNumber = 2 // Second POST fails

        await service.notifySuccess()

        XCTAssertEqual(poster.postCalls.count, 2) // tried /a (ok) and /b (fail)
        XCTAssertEqual(queue.count, 2) // /b re-queued at front, /c still in queue
        XCTAssertEqual(queue.items[0].path, "/b")
        XCTAssertEqual(queue.items[1].path, "/c")
    }

    // MARK: - Drain resumes on next success

    func testDrainResumesAfterFailureThenSuccess() async {
        let (service, queue, poster) = makeService()

        queue.enqueue(path: "/a", payload: Data("1".utf8))
        queue.enqueue(path: "/b", payload: Data("2".utf8))

        poster.failOnCallNumber = 1 // First POST fails
        await service.notifySuccess()

        XCTAssertEqual(queue.count, 2) // /a re-queued, /b still there

        // Now fix the poster and notify success again
        poster.failOnCallNumber = nil
        await service.notifySuccess()

        XCTAssertTrue(queue.isEmpty)
        // Total calls: 1 (failed /a) + 2 (success /a, /b) = 3
        XCTAssertEqual(poster.postCalls.count, 3)
    }

    // MARK: - Payload forwarding

    func testDrainSendsCorrectPayloadAndPath() async {
        let (service, queue, poster) = makeService()
        let payload = Data("{\"lat\":33.4}".utf8)

        queue.enqueue(path: "/location", payload: payload)

        await service.notifySuccess()

        XCTAssertEqual(poster.postCalls[0].path, "/location")
        XCTAssertEqual(poster.postCalls[0].payload, payload)
    }

    // MARK: - isDraining

    func testIsDrainingFalseInitially() {
        let (service, _, _) = makeService()
        XCTAssertFalse(service.isDraining)
    }
}

// MARK: - Mock Raw Poster

/// Posts raw Data payloads to a path, used for replaying queued items.
final class MockRawPoster: RawPayloadPosting {
    struct PostCall {
        let path: String
        let payload: Data
    }

    var postCalls: [PostCall] = []
    var failOnCallNumber: Int? // 1-indexed

    func postRawPayload(_ payload: Data, to path: String) async throws {
        postCalls.append(PostCall(path: path, payload: payload))
        if let failOn = failOnCallNumber, postCalls.count == failOn {
            throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Simulated failure"])
        }
    }
}
