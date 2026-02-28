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

    func testInitialStateHasMainFallback() {
        XCTAssertEqual(viewModel.sessions.count, 1)
        XCTAssertEqual(viewModel.sessions[0].key, "agent:main:main")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.selectedSessionKey, "agent:main:main")
    }

    // MARK: - Load Sessions

    func testLoadSessionsPopulatesFilteredList() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:discord:123", title: "Morning chat", lastMessage: "Good morning!", channelType: "discord"),
            GatewaySession(key: "agent:main:discord:456", title: "Project discussion", lastMessage: nil, channelType: "discord")
        ]

        await viewModel.loadSessions()

        // 2 discord sessions + Main fallback = 3
        XCTAssertEqual(viewModel.sessions.count, 3)
        XCTAssertTrue(viewModel.sessions.contains(where: { $0.key == "agent:main:main" }))
        XCTAssertTrue(viewModel.sessions.contains(where: { $0.key == "agent:main:discord:123" && $0.lastMessage == "Good morning!" }))
        XCTAssertTrue(viewModel.sessions.contains(where: { $0.key == "agent:main:discord:456" && $0.lastMessage == nil }))
    }

    func testLoadSessionsSetsLoadingFalseAfterFetch() async {
        await viewModel.loadSessions()
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadSessionsOnErrorKeepsMainFallback() async {
        lister.shouldThrow = NSError(domain: "test", code: 1)

        await viewModel.loadSessions()

        // Main fallback always present even on error
        XCTAssertEqual(viewModel.sessions.count, 1)
        XCTAssertEqual(viewModel.sessions[0].key, "agent:main:main")
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

    func testDefaultSelectionIsMain() {
        XCTAssertEqual(viewModel.activeSessionKey, "agent:main:main")
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

    // MARK: - isSessionSelected always true

    func testIsSessionSelectedAlwaysTrue() {
        XCTAssertTrue(viewModel.isSessionSelected)
    }
}

// MARK: - Filtering & Auto-Select

@MainActor
extension SessionPickerViewModelTests {

    func testLoadSessionsFiltersToMainAndDiscordOnly() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:discord:123", title: "Discord chat", lastMessage: nil, channelType: "discord"),
            GatewaySession(key: "agent:main:whatsapp:456", title: "WhatsApp chat", lastMessage: nil, channelType: "whatsapp"),
            GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main"),
            GatewaySession(key: "agent:main:cron:789", title: "Cron job", lastMessage: nil, channelType: "cron"),
        ]

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.sessions.count, 2)
        XCTAssertTrue(viewModel.sessions.contains(where: { $0.key == "agent:main:main" }))
        XCTAssertTrue(viewModel.sessions.contains(where: { $0.key == "agent:main:discord:123" }))
        XCTAssertFalse(viewModel.sessions.contains(where: { $0.key.contains("whatsapp") }))
        XCTAssertFalse(viewModel.sessions.contains(where: { $0.key.contains("cron") }))
    }

    func testLoadSessionsFiltersOutNonDiscordNonMainSessions() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:telegram:111", title: "Telegram", lastMessage: nil, channelType: "telegram"),
            GatewaySession(key: "agent:scrapper:subagent:222", title: "Sub-agent", lastMessage: nil, channelType: nil),
        ]

        await viewModel.loadSessions()

        // Only Main fallback should remain
        XCTAssertEqual(viewModel.sessions.count, 1)
        XCTAssertEqual(viewModel.sessions[0].key, "agent:main:main")
    }

    func testLoadSessionsAutoSelectsMainSession() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:discord:123", title: "Discord", lastMessage: nil, channelType: "discord"),
            GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main"),
            GatewaySession(key: "agent:main:discord:456", title: "Other", lastMessage: nil, channelType: "discord"),
        ]

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.selectedSessionKey, "agent:main:main")
    }

    func testLoadSessionsFallsBackToMainFallbackWhenNoMainInResult() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:discord:123", title: "Discord", lastMessage: nil, channelType: "discord"),
            GatewaySession(key: "agent:main:discord:456", title: "Other", lastMessage: nil, channelType: "discord"),
        ]

        await viewModel.loadSessions()

        // Main fallback is always inserted
        XCTAssertEqual(viewModel.selectedSessionKey, "agent:main:main")
    }

    func testLoadSessionsDoesNotOverrideExistingSelection() async {
        viewModel.selectedSessionKey = "agent:main:discord:456"
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main"),
            GatewaySession(key: "agent:main:discord:456", title: "Other", lastMessage: nil, channelType: "discord"),
        ]

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.selectedSessionKey, "agent:main:discord:456")
    }

    func testLoadSessionsClearsSelectionIfSelectedSessionNoLongerExists() async {
        viewModel.selectedSessionKey = "gone"
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main"),
        ]

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.selectedSessionKey, "agent:main:main")
    }

    func testLoadSessionsEmptyResultSelectsMainFallback() async {
        viewModel.selectedSessionKey = "old"
        lister.sessionsToReturn = []

        await viewModel.loadSessions()

        // Main fallback always present
        XCTAssertEqual(viewModel.selectedSessionKey, "agent:main:main")
    }

    func testSelectedSessionTitleReturnsMatchingTitle() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main"),
            GatewaySession(key: "agent:main:discord:123", title: "Discord chat", lastMessage: nil, channelType: "discord"),
        ]
        await viewModel.loadSessions()
        viewModel.selectedSessionKey = "agent:main:discord:123"

        XCTAssertEqual(viewModel.selectedSessionTitle, "Discord chat")
    }

    func testSelectedSessionTitleDefaultsToMain() {
        XCTAssertEqual(viewModel.selectedSessionTitle, "Main")
    }

    func testSelectedSessionTitleDoesNotContainNewConversation() async {
        lister.sessionsToReturn = []
        await viewModel.loadSessions()

        XCTAssertNotEqual(viewModel.selectedSessionTitle, "New conversation")
    }
}
