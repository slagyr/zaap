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
            GatewaySession(key: "abc-123", title: "Morning chat", lastMessage: "Good morning!", channelType: "discord"),
            GatewaySession(key: "def-456", title: "Project discussion", lastMessage: nil, channelType: "discord")
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
        let session = GatewaySession(key: "test-key", title: "Test", lastMessage: nil, channelType: "discord")
        XCTAssertEqual(session.id, "test-key")
    }

    func testGatewaySessionEquality() {
        let a = GatewaySession(key: "k1", title: "T1", lastMessage: "m1", channelType: "discord")
        let b = GatewaySession(key: "k1", title: "T1", lastMessage: "m1", channelType: "discord")
        let c = GatewaySession(key: "k2", title: "T1", lastMessage: "m1", channelType: "discord")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

// MARK: - Discord Filtering & Auto-Select Extensions

@MainActor
extension SessionPickerViewModelTests {

    func testLoadSessionsFiltersToDiscordOnly() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "d1", title: "Discord chat", lastMessage: nil, channelType: "discord"),
            GatewaySession(key: "w1", title: "WhatsApp chat", lastMessage: nil, channelType: "whatsapp"),
            GatewaySession(key: "d2", title: "Another Discord", lastMessage: nil, channelType: "discord"),
        ]

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.sessions.count, 2)
        XCTAssertEqual(viewModel.sessions[0].key, "d1")
        XCTAssertEqual(viewModel.sessions[1].key, "d2")
    }

    func testLoadSessionsFiltersOutNilChannelType() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "d1", title: "Discord", lastMessage: nil, channelType: "discord"),
            GatewaySession(key: "n1", title: "Unknown", lastMessage: nil, channelType: nil),
        ]

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.sessions.count, 1)
        XCTAssertEqual(viewModel.sessions[0].key, "d1")
    }

    func testLoadSessionsAutoSelectsFirstSession() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "d1", title: "Most recent", lastMessage: nil, channelType: "discord"),
            GatewaySession(key: "d2", title: "Older", lastMessage: nil, channelType: "discord"),
        ]

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.selectedSessionKey, "d1")
    }

    func testLoadSessionsDoesNotOverrideExistingSelection() async {
        viewModel.selectedSessionKey = "d2"
        lister.sessionsToReturn = [
            GatewaySession(key: "d1", title: "Most recent", lastMessage: nil, channelType: "discord"),
            GatewaySession(key: "d2", title: "Older", lastMessage: nil, channelType: "discord"),
        ]

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.selectedSessionKey, "d2")
    }

    func testLoadSessionsClearsSelectionIfSelectedSessionNoLongerExists() async {
        viewModel.selectedSessionKey = "gone"
        lister.sessionsToReturn = [
            GatewaySession(key: "d1", title: "Only one", lastMessage: nil, channelType: "discord"),
        ]

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.selectedSessionKey, "d1")
    }

    func testLoadSessionsNoDiscordSessionsClearsSelection() async {
        viewModel.selectedSessionKey = "old"
        lister.sessionsToReturn = [
            GatewaySession(key: "w1", title: "WhatsApp", lastMessage: nil, channelType: "whatsapp"),
        ]

        await viewModel.loadSessions()

        XCTAssertNil(viewModel.selectedSessionKey)
    }

    func testIsSessionSelectedReturnsFalseWhenNoSelection() {
        XCTAssertFalse(viewModel.isSessionSelected)
    }

    func testIsSessionSelectedReturnsTrueWhenSelected() {
        viewModel.selectedSessionKey = "abc"
        XCTAssertTrue(viewModel.isSessionSelected)
    }
}
