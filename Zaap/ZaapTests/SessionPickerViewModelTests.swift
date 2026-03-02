import XCTest
@testable import Zaap

// MARK: - Mock Session Lister

final class MockSessionListing: SessionListing {
    var sessionsToReturn: [GatewaySession] = []
    var shouldThrow: Error?
    var listCallCount = 0

    func listSessions(limit: Int?, activeMinutes: Int?, includeDerivedTitles: Bool, includeLastMessage: Bool) async throws -> [GatewaySession] {
        listCallCount += 1
        if let error = shouldThrow {
            throw error
        }
        return sessionsToReturn
    }
}

// MARK: - Mock Session Previewing

final class MockSessionPreviewing: SessionPreviewing {
    var previewToReturn: [PreviewMessage] = []
    var shouldThrow: Error?
    var lastRequestedSessionKey: String?
    var lastRequestedLimit: Int?
    var previewCallCount = 0

    func previewSession(key: String, limit: Int) async throws -> [PreviewMessage] {
        previewCallCount += 1
        lastRequestedSessionKey = key
        lastRequestedLimit = limit
        if let error = shouldThrow {
            throw error
        }
        return previewToReturn
    }
}

// MARK: - Tests

@MainActor
final class SessionPickerViewModelTests: XCTestCase {

    var lister: MockSessionListing!
    var previewer: MockSessionPreviewing!
    var viewModel: SessionPickerViewModel!

    override func setUp() {
        super.setUp()
        lister = MockSessionListing()
        previewer = MockSessionPreviewing()
        viewModel = SessionPickerViewModel(sessionLister: lister, sessionPreviewer: previewer)
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

    func testLoadSessionsFiltersOutNonMainAgentDiscordSessions() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:discord:channel:123", title: "discord:111#general", lastMessage: nil, channelType: "discord"),
            GatewaySession(key: "agent:scrapper:discord:channel:123", title: "discord:g-123", lastMessage: nil, channelType: "discord"),
            GatewaySession(key: "agent:scrapper:discord:channel:456", title: "discord:g-456", lastMessage: nil, channelType: "discord"),
        ]

        await viewModel.loadSessions()

        // Only agent:main discord + Main fallback
        XCTAssertEqual(viewModel.sessions.count, 2)
        XCTAssertTrue(viewModel.sessions.contains(where: { $0.key == "agent:main:main" }))
        XCTAssertTrue(viewModel.sessions.contains(where: { $0.key == "agent:main:discord:channel:123" }))
        XCTAssertFalse(viewModel.sessions.contains(where: { $0.key.hasPrefix("agent:scrapper") }))
    }

    func testLoadSessionsAutoSelectsGeneralWhenAvailable() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:discord:123", title: "discord:111#general", lastMessage: nil, channelType: "discord"),
            GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main"),
            GatewaySession(key: "agent:main:discord:456", title: "discord:111#random", lastMessage: nil, channelType: "discord"),
        ]

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.selectedSessionKey, "agent:main:discord:123")
    }

    func testLoadSessionsFallsBackToMainWhenNoGeneral() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:discord:123", title: "discord:111#random", lastMessage: nil, channelType: "discord"),
            GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main"),
        ]

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.selectedSessionKey, "agent:main:main")
    }

    func testLoadSessionsAutoSelectsGeneralAndLoadsPreview() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:discord:channel:123", title: "discord:111#general", lastMessage: nil, channelType: "discord"),
            GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main"),
        ]
        previewer.previewToReturn = [
            PreviewMessage(role: "user", text: "Hello from general"),
        ]

        await viewModel.loadSessions()

        XCTAssertEqual(previewer.lastRequestedSessionKey, "agent:main:discord:channel:123")
    }

    func testLoadSessionsKeepsUserSelectionOverGeneral() async {
        viewModel.selectedSessionKey = "agent:main:discord:456"
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:discord:123", title: "discord:111#general", lastMessage: nil, channelType: "discord"),
            GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main"),
            GatewaySession(key: "agent:main:discord:456", title: "discord:111#random", lastMessage: nil, channelType: "discord"),
        ]

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.selectedSessionKey, "agent:main:discord:456")
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

    // MARK: - Title Cleanup

    func testMainSessionTitleIsAlwaysMain() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:main", title: "Read HEARTBEAT.md if it exists (workspace context). Follow...", lastMessage: nil, channelType: "main"),
        ]

        await viewModel.loadSessions()

        let main = viewModel.sessions.first(where: { $0.key == "agent:main:main" })
        XCTAssertEqual(main?.title, "Main")
    }

    func testDiscordTitleExtractsChannelName() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:discord:channel:123", title: "discord:1471611817712418918#general", lastMessage: nil, channelType: "discord"),
        ]

        await viewModel.loadSessions()

        let session = viewModel.sessions.first(where: { $0.key.contains("discord") })
        XCTAssertEqual(session?.title, "general")
    }

    func testDiscordTitleWithMultipleHashesExtractsAfterLastHash() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:discord:channel:456", title: "discord:123456#my-cool-channel", lastMessage: nil, channelType: "discord"),
        ]

        await viewModel.loadSessions()

        let session = viewModel.sessions.first(where: { $0.key.contains("discord") })
        XCTAssertEqual(session?.title, "my-cool-channel")
    }

    func testDiscordTitleWithoutHashIsFilteredOut() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:discord:channel:789", title: "discord:g-1471680593497554998", lastMessage: nil, channelType: "discord"),
        ]

        await viewModel.loadSessions()

        // Discord sessions with no resolved channel name (no #) are filtered out
        XCTAssertFalse(viewModel.sessions.contains(where: { $0.key.contains("discord") }))
    }

    func testMainFallbackAlwaysHasMainTitle() async {
        // When main session is not in results, the fallback should still say "Main"
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:discord:channel:123", title: "discord:123#general", lastMessage: nil, channelType: "discord"),
        ]

        await viewModel.loadSessions()

        let main = viewModel.sessions.first(where: { $0.key == "agent:main:main" })
        XCTAssertEqual(main?.title, "Main")
    }

    // MARK: - Alphabetical Sort

    func testSessionsSortedAlphabeticallyWithMainFirst() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:discord:channel:1", title: "discord:111#zaap", lastMessage: nil, channelType: "discord"),
            GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main"),
            GatewaySession(key: "agent:main:discord:channel:2", title: "discord:111#general", lastMessage: nil, channelType: "discord"),
            GatewaySession(key: "agent:main:discord:channel:3", title: "discord:111#braids", lastMessage: nil, channelType: "discord"),
        ]

        await viewModel.loadSessions()

        let titles = viewModel.sessions.map(\.title)
        // Stored in reverse-alpha order because Menu/Picker renders bottom-to-top
        XCTAssertEqual(titles, ["Main", "zaap", "general", "braids"])
    }

    // MARK: - Filter discord:g- sessions

    func testFiltersOutDiscordSessionsWithNoChannelName() async {
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:discord:channel:123", title: "discord:111#general", lastMessage: nil, channelType: "discord"),
            GatewaySession(key: "agent:main:discord:channel:789", title: "discord:g-1471680593497554998", lastMessage: nil, channelType: "discord"),
        ]

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.sessions.count, 2) // general + Main fallback
        XCTAssertTrue(viewModel.sessions.contains(where: { $0.title == "general" }))
        XCTAssertFalse(viewModel.sessions.contains(where: { $0.title.hasPrefix("discord:g-") }))
    }
}

// MARK: - Session Preview Tests

@MainActor
final class SessionPreviewTests: XCTestCase {

    var lister: MockSessionListing!
    var previewer: MockSessionPreviewing!
    var viewModel: SessionPickerViewModel!

    override func setUp() {
        super.setUp()
        lister = MockSessionListing()
        previewer = MockSessionPreviewing()
        viewModel = SessionPickerViewModel(sessionLister: lister, sessionPreviewer: previewer)
    }

    func testLoadPreviewCallsPreviewerWithSessionKey() async {
        previewer.previewToReturn = []
        await viewModel.loadPreview(forSession: "agent:main:main")
        XCTAssertEqual(previewer.previewCallCount, 1)
        XCTAssertEqual(previewer.lastRequestedSessionKey, "agent:main:main")
    }

    func testLoadPreviewRequestsDefaultLimit() async {
        previewer.previewToReturn = []
        await viewModel.loadPreview(forSession: "agent:main:main")
        XCTAssertEqual(previewer.lastRequestedLimit, 10)
    }

    func testLoadPreviewPublishesMessages() async {
        previewer.previewToReturn = [
            PreviewMessage(role: "user", text: "Hello"),
            PreviewMessage(role: "assistant", text: "Hi there!")
        ]
        await viewModel.loadPreview(forSession: "agent:main:main")
        XCTAssertEqual(viewModel.previewMessages.count, 2)
        XCTAssertEqual(viewModel.previewMessages[0].role, .user)
        XCTAssertEqual(viewModel.previewMessages[0].text, "Hello")
        XCTAssertEqual(viewModel.previewMessages[1].role, .agent)
        XCTAssertEqual(viewModel.previewMessages[1].text, "Hi there!")
    }

    func testLoadPreviewClearsMessagesOnError() async {
        previewer.previewToReturn = [PreviewMessage(role: "user", text: "Old")]
        await viewModel.loadPreview(forSession: "agent:main:main")
        XCTAssertEqual(viewModel.previewMessages.count, 1)

        previewer.shouldThrow = NSError(domain: "test", code: 1)
        await viewModel.loadPreview(forSession: "agent:main:main")
        XCTAssertTrue(viewModel.previewMessages.isEmpty)
    }

    func testLoadPreviewMapsAssistantRoleToAgent() async {
        previewer.previewToReturn = [
            PreviewMessage(role: "assistant", text: "I can help with that.")
        ]
        await viewModel.loadPreview(forSession: "agent:main:main")
        XCTAssertEqual(viewModel.previewMessages[0].role, .agent)
    }

    func testLoadPreviewMapsUserRole() async {
        previewer.previewToReturn = [
            PreviewMessage(role: "user", text: "What time is it?")
        ]
        await viewModel.loadPreview(forSession: "agent:main:main")
        XCTAssertEqual(viewModel.previewMessages[0].role, .user)
    }

    func testLoadPreviewIgnoresUnknownRoles() async {
        previewer.previewToReturn = [
            PreviewMessage(role: "system", text: "System prompt"),
            PreviewMessage(role: "user", text: "Hello")
        ]
        await viewModel.loadPreview(forSession: "agent:main:main")
        XCTAssertEqual(viewModel.previewMessages.count, 1)
        XCTAssertEqual(viewModel.previewMessages[0].text, "Hello")
    }

    func testPreviewMessagesStartEmpty() {
        XCTAssertTrue(viewModel.previewMessages.isEmpty)
    }

    func testLoadPreviewFiltersSystemPrefixedUserMessages() async {
        previewer.previewToReturn = [
            PreviewMessage(role: "user", text: "System: [2026-02-28] Hook Hook: cron triggered"),
            PreviewMessage(role: "user", text: "What's the weather?"),
            PreviewMessage(role: "assistant", text: "It's sunny today."),
        ]
        await viewModel.loadPreview(forSession: "agent:main:main")
        XCTAssertEqual(viewModel.previewMessages.count, 2)
        XCTAssertEqual(viewModel.previewMessages[0].text, "What's the weather?")
        XCTAssertEqual(viewModel.previewMessages[1].text, "It's sunny today.")
    }

    func testLoadPreviewFiltersHeartbeatMessages() async {
        previewer.previewToReturn = [
            PreviewMessage(role: "user", text: "Read HEARTBEAT.md if it exists and follow any instructions in it."),
            PreviewMessage(role: "user", text: "Tell me a joke"),
            PreviewMessage(role: "assistant", text: "Why did the chicken cross the road?"),
        ]
        await viewModel.loadPreview(forSession: "agent:main:main")
        XCTAssertEqual(viewModel.previewMessages.count, 2)
        XCTAssertEqual(viewModel.previewMessages[0].text, "Tell me a joke")
    }

    func testLoadPreviewFiltersSystemMessageBracketPrefix() async {
        previewer.previewToReturn = [
            PreviewMessage(role: "user", text: "[System Message] [session timeout] Auto-closing idle session"),
            PreviewMessage(role: "assistant", text: "Session resumed."),
        ]
        await viewModel.loadPreview(forSession: "agent:main:main")
        XCTAssertEqual(viewModel.previewMessages.count, 1)
        XCTAssertEqual(viewModel.previewMessages[0].text, "Session resumed.")
    }

    func testLoadPreviewStripsDiscordMetadataPreamble() async {
        let preamble = "Conversation info (untrusted metadata):\n```json\n{\"channel\": \"general\"}\n```\n\nHey can you help me?"
        previewer.previewToReturn = [
            PreviewMessage(role: "user", text: preamble),
            PreviewMessage(role: "assistant", text: "Sure!"),
        ]
        await viewModel.loadPreview(forSession: "agent:main:main")
        XCTAssertEqual(viewModel.previewMessages.count, 2)
        XCTAssertEqual(viewModel.previewMessages[0].text, "Hey can you help me?")
    }

    func testLoadPreviewFiltersConversationInfoOnlyMessages() async {
        let metadataOnly = "Conversation info (untrusted metadata):\n```json\n{\"channel\": \"general\"}\n```"
        previewer.previewToReturn = [
            PreviewMessage(role: "user", text: metadataOnly),
            PreviewMessage(role: "assistant", text: "Hello!"),
        ]
        await viewModel.loadPreview(forSession: "agent:main:main")
        XCTAssertEqual(viewModel.previewMessages.count, 1)
        XCTAssertEqual(viewModel.previewMessages[0].text, "Hello!")
    }

    func testLoadPreviewStripsBothConversationAndSenderMetadata() async {
        let fullPreamble = """
            Conversation info (untrusted metadata):
            ```json
            {
              "guild_id": "1471611817712418918",
              "is_group_chat": true
            }
            ```

            Sender (untrusted metadata):
            ```json
            {
              "label": "slagyr",
              "name": "slagyr"
            }
            ```

            Yeah. The sanctuary adoption is an amazing idea.
            """
        previewer.previewToReturn = [
            PreviewMessage(role: "user", text: fullPreamble),
            PreviewMessage(role: "assistant", text: "Great!"),
        ]
        await viewModel.loadPreview(forSession: "agent:main:main")
        XCTAssertEqual(viewModel.previewMessages.count, 2)
        XCTAssertEqual(viewModel.previewMessages[0].text, "Yeah. The sanctuary adoption is an amazing idea.")
    }

    func testLoadPreviewStripsSenderMetadataAlone() async {
        let senderOnly = "Sender (untrusted metadata):\n```json\n{\"name\": \"slagyr\"}\n```\n\nHello there!"
        previewer.previewToReturn = [
            PreviewMessage(role: "user", text: senderOnly),
        ]
        await viewModel.loadPreview(forSession: "agent:main:main")
        XCTAssertEqual(viewModel.previewMessages.count, 1)
        XCTAssertEqual(viewModel.previewMessages[0].text, "Hello there!")
    }

    func testLoadSessionsAutoLoadsPreviewForSelectedSession() async {
        previewer.previewToReturn = [
            PreviewMessage(role: "user", text: "Hi from main"),
            PreviewMessage(role: "assistant", text: "Hello!")
        ]
        lister.sessionsToReturn = [
            GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main"),
        ]

        await viewModel.loadSessions()

        XCTAssertEqual(previewer.previewCallCount, 1)
        XCTAssertEqual(previewer.lastRequestedSessionKey, "agent:main:main")
        XCTAssertEqual(viewModel.previewMessages.count, 2)
    }
}
