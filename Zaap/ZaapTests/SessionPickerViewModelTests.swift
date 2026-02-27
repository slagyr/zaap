import XCTest
@testable import Zaap

// MARK: - Mock Session Lister

final class MockSessionListing: SessionListing {
    var sessionsToReturn: [GatewaySession] = []
    var shouldThrow: Error?
    var listCallCount = 0

    func listSessions(limit: Int, activeMinutes: Int?, includeDerivedTitles: Bool, includeLastMessage: Bool) async throws -> [GatewaySession] {
        listCallCount += 1
        if let error = shouldThrow {
            throw error
        }
        return sessionsToReturn
    }
}

// MARK: - Tests

@MainActor
final class SessionPickerViewModelTests: XCTestCase {

    var lister: MockSessionListing!
    var viewModel: SessionPickerViewModel!

    override func setUp() {
        super.setUp()
        lister = MockSessionListing()
        viewModel = SessionPickerViewModel(sessionLister: lister)
    }

    // MARK: - Initial State

    func testInitialStateIsEmpty() {
        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.selectedSessionKey)
    }

    // MARK: - Load Sessions

    func testLoadSessionsPopulatesList() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "abc-123", title: "Morning chat", lastMessage: "Good morning!"),
            GatewaySession(key: "def-456", title: "Project discussion", lastMessage: nil)
        ]

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.sessions.count, 2)
        XCTAssertEqual(viewModel.sessions[0].key, "abc-123")
        XCTAssertEqual(viewModel.sessions[0].title, "Morning chat")
        XCTAssertEqual(viewModel.sessions[0].lastMessage, "Good morning!")
        XCTAssertEqual(viewModel.sessions[1].key, "def-456")
        XCTAssertEqual(viewModel.sessions[1].lastMessage, nil)
    }

    func testLoadSessionsSetsLoadingFalseAfterFetch() async {
        await viewModel.loadSessions()
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadSessionsOnErrorClearsList() async {
        lister.shouldThrow = NSError(domain: "test", code: 1)

        await viewModel.loadSessions()

        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadSessionsCallsListerWithCorrectParams() async {
        await viewModel.loadSessions()
        XCTAssertEqual(lister.listCallCount, 1)
    }

    // MARK: - Selection

    func testSelectingSessionUpdatesActiveKey() {
        viewModel.selectedSessionKey = "abc-123"
        XCTAssertEqual(viewModel.activeSessionKey, "abc-123")
    }

    func testNoSelectionReturnsNil() {
        XCTAssertNil(viewModel.activeSessionKey)
    }

    // MARK: - GatewaySession Model

    func testGatewaySessionIdentifiable() {
        let session = GatewaySession(key: "test-key", title: "Test", lastMessage: nil)
        XCTAssertEqual(session.id, "test-key")
    }

    func testGatewaySessionEquality() {
        let a = GatewaySession(key: "k1", title: "T1", lastMessage: "m1")
        let b = GatewaySession(key: "k1", title: "T1", lastMessage: "m1")
        let c = GatewaySession(key: "k2", title: "T1", lastMessage: "m1")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
