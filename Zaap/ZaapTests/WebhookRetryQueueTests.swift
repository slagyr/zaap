import XCTest
@testable import Zaap

final class WebhookRetryQueueTests: XCTestCase {

    // MARK: - RetryQueueItem

    func testRetryQueueItemStoresPathPayloadAndTimestamp() {
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        let payload = Data("{\"lat\":33.4}".utf8)
        let item = RetryQueueItem(path: "/location", payload: payload, originalTimestamp: timestamp)

        XCTAssertEqual(item.path, "/location")
        XCTAssertEqual(item.payload, payload)
        XCTAssertEqual(item.originalTimestamp, timestamp)
    }

    func testRetryQueueItemIsIdentifiable() {
        let item = RetryQueueItem(path: "/location", payload: Data(), originalTimestamp: Date())
        let item2 = RetryQueueItem(path: "/location", payload: Data(), originalTimestamp: Date())
        XCTAssertNotEqual(item.id, item2.id)
    }

    func testRetryQueueItemIsCodable() throws {
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        let payload = Data("{\"lat\":33.4}".utf8)
        let item = RetryQueueItem(path: "/location", payload: payload, originalTimestamp: timestamp)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RetryQueueItem.self, from: data)

        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.path, item.path)
        XCTAssertEqual(decoded.payload, item.payload)
        XCTAssertEqual(decoded.originalTimestamp.timeIntervalSince1970, item.originalTimestamp.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - Enqueue

    func testEnqueueAddsItemToQueue() {
        let queue = WebhookRetryQueue(skipLoad: true)
        let payload = Data("{\"lat\":33.4}".utf8)

        queue.enqueue(path: "/location", payload: payload)

        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.items[0].path, "/location")
        XCTAssertEqual(queue.items[0].payload, payload)
    }

    func testEnqueueMultipleItemsPreservesOrder() {
        let queue = WebhookRetryQueue(skipLoad: true)

        queue.enqueue(path: "/location", payload: Data("1".utf8))
        queue.enqueue(path: "/heartrate", payload: Data("2".utf8))
        queue.enqueue(path: "/sleep", payload: Data("3".utf8))

        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue.items[0].path, "/location")
        XCTAssertEqual(queue.items[1].path, "/heartrate")
        XCTAssertEqual(queue.items[2].path, "/sleep")
    }

    func testQueueStartsEmpty() {
        let queue = WebhookRetryQueue(skipLoad: true)
        XCTAssertEqual(queue.count, 0)
        XCTAssertTrue(queue.items.isEmpty)
    }

    // MARK: - Deduplication

    func testEnqueueRejectsDuplicatePayloadAndPath() {
        let queue = WebhookRetryQueue(skipLoad: true)
        let payload = Data("{\"lat\":33.4}".utf8)

        queue.enqueue(path: "/location", payload: payload)
        queue.enqueue(path: "/location", payload: payload)

        XCTAssertEqual(queue.count, 1)
    }

    func testEnqueueAllowsSamePayloadDifferentPath() {
        let queue = WebhookRetryQueue(skipLoad: true)
        let payload = Data("{\"lat\":33.4}".utf8)

        queue.enqueue(path: "/location", payload: payload)
        queue.enqueue(path: "/heartrate", payload: payload)

        XCTAssertEqual(queue.count, 2)
    }

    func testEnqueueAllowsSamePathDifferentPayload() {
        let queue = WebhookRetryQueue(skipLoad: true)

        queue.enqueue(path: "/location", payload: Data("1".utf8))
        queue.enqueue(path: "/location", payload: Data("2".utf8))

        XCTAssertEqual(queue.count, 2)
    }

    // MARK: - Max queue size

    func testMaxQueueSizeDefaultIs500() {
        let queue = WebhookRetryQueue(skipLoad: true)
        XCTAssertEqual(queue.maxSize, 500)
    }

    func testEnqueueDropsOldestWhenExceedingMaxSize() {
        let queue = WebhookRetryQueue(maxSize: 3, skipLoad: true)

        queue.enqueue(path: "/a", payload: Data("1".utf8))
        queue.enqueue(path: "/b", payload: Data("2".utf8))
        queue.enqueue(path: "/c", payload: Data("3".utf8))
        queue.enqueue(path: "/d", payload: Data("4".utf8))

        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue.items[0].path, "/b")
        XCTAssertEqual(queue.items[2].path, "/d")
    }

    func testEnqueueDropsMultipleOldestWhenFarOverCap() {
        let queue = WebhookRetryQueue(maxSize: 2, skipLoad: true)

        for i in 0..<5 {
            queue.enqueue(path: "/\(i)", payload: Data("\(i)".utf8))
        }

        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.items[0].path, "/3")
        XCTAssertEqual(queue.items[1].path, "/4")
    }

    // MARK: - TTL pruning

    func testPruneRemovesItemsOlderThan7Days() {
        let queue = WebhookRetryQueue(skipLoad: true)
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        let sixDaysAgo = Date().addingTimeInterval(-6 * 24 * 60 * 60)

        queue.enqueue(path: "/old", payload: Data("old".utf8), originalTimestamp: eightDaysAgo)
        queue.enqueue(path: "/recent", payload: Data("new".utf8), originalTimestamp: sixDaysAgo)

        queue.pruneExpired()

        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.items[0].path, "/recent")
    }

    func testPruneKeepsItemsExactly7DaysOld() {
        let queue = WebhookRetryQueue(skipLoad: true)
        let exactlySevenDays = Date().addingTimeInterval(-7 * 24 * 60 * 60 + 60) // 7 days minus 1 minute

        queue.enqueue(path: "/edge", payload: Data("edge".utf8), originalTimestamp: exactlySevenDays)

        queue.pruneExpired()

        XCTAssertEqual(queue.count, 1)
    }

    func testPruneRemovesAllExpiredItems() {
        let queue = WebhookRetryQueue(skipLoad: true)
        let tenDaysAgo = Date().addingTimeInterval(-10 * 24 * 60 * 60)

        queue.enqueue(path: "/a", payload: Data("1".utf8), originalTimestamp: tenDaysAgo)
        queue.enqueue(path: "/b", payload: Data("2".utf8), originalTimestamp: tenDaysAgo)

        queue.pruneExpired()

        XCTAssertEqual(queue.count, 0)
    }

    // MARK: - Dequeue

    func testDequeueReturnsOldestItem() {
        let queue = WebhookRetryQueue(skipLoad: true)
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)

        queue.enqueue(path: "/first", payload: Data("1".utf8), originalTimestamp: t1)
        queue.enqueue(path: "/second", payload: Data("2".utf8), originalTimestamp: t2)

        let item = queue.dequeue()

        XCTAssertEqual(item?.path, "/first")
        XCTAssertEqual(queue.count, 1)
    }

    func testDequeueReturnsNilWhenEmpty() {
        let queue = WebhookRetryQueue(skipLoad: true)
        XCTAssertNil(queue.dequeue())
    }

    func testDequeueRemovesItemFromQueue() {
        let queue = WebhookRetryQueue(skipLoad: true)
        queue.enqueue(path: "/a", payload: Data("1".utf8))

        _ = queue.dequeue()

        XCTAssertEqual(queue.count, 0)
    }

    // MARK: - isEmpty

    func testIsEmptyReturnsTrueForNewQueue() {
        let queue = WebhookRetryQueue(skipLoad: true)
        XCTAssertTrue(queue.isEmpty)
    }

    func testIsEmptyReturnsFalseWithItems() {
        let queue = WebhookRetryQueue(skipLoad: true)
        queue.enqueue(path: "/a", payload: Data("1".utf8))
        XCTAssertFalse(queue.isEmpty)
    }

    // MARK: - onCountChange Callback

    func testOnCountChangeFiresAfterEnqueue() {
        let queue = WebhookRetryQueue(skipLoad: true)
        var reported: [Int] = []
        queue.onCountChange = { reported.append($0) }

        queue.enqueue(path: "/a", payload: Data("1".utf8))

        XCTAssertEqual(reported, [1])
    }

    func testOnCountChangeFiresAfterDequeue() {
        let queue = WebhookRetryQueue(skipLoad: true)
        queue.enqueue(path: "/a", payload: Data("1".utf8))

        var reported: [Int] = []
        queue.onCountChange = { reported.append($0) }

        _ = queue.dequeue()

        XCTAssertEqual(reported, [0])
    }

    func testOnCountChangeFiresAfterPruneExpired() {
        let queue = WebhookRetryQueue(skipLoad: true)
        let tenDaysAgo = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        queue.enqueue(path: "/old", payload: Data("1".utf8), originalTimestamp: tenDaysAgo)

        var reported: [Int] = []
        queue.onCountChange = { reported.append($0) }

        queue.pruneExpired()

        XCTAssertEqual(reported, [0])
    }

    func testOnCountChangeFiresAfterRequeueAtFront() {
        let queue = WebhookRetryQueue(skipLoad: true)
        queue.enqueue(path: "/a", payload: Data("1".utf8))
        let item = queue.dequeue()!

        var reported: [Int] = []
        queue.onCountChange = { reported.append($0) }

        queue.requeueAtFront(item)

        XCTAssertEqual(reported, [1])
    }

    func testOnCountChangeDoesNotFireForDuplicateEnqueue() {
        let queue = WebhookRetryQueue(skipLoad: true)
        let payload = Data("1".utf8)
        queue.enqueue(path: "/a", payload: payload)

        var reported: [Int] = []
        queue.onCountChange = { reported.append($0) }

        queue.enqueue(path: "/a", payload: payload) // duplicate

        XCTAssertTrue(reported.isEmpty)
    }

    func testOnCountChangeReportsCorrectCountAfterMultipleEnqueues() {
        let queue = WebhookRetryQueue(skipLoad: true)
        var reported: [Int] = []
        queue.onCountChange = { reported.append($0) }

        queue.enqueue(path: "/a", payload: Data("1".utf8))
        queue.enqueue(path: "/b", payload: Data("2".utf8))
        queue.enqueue(path: "/c", payload: Data("3".utf8))

        XCTAssertEqual(reported, [1, 2, 3])
    }
}
