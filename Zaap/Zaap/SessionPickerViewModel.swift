import Foundation

// MARK: - Model

struct GatewaySession: Equatable, Identifiable {
    let key: String
    let title: String
    let lastMessage: String?
    let channelType: String?

    var id: String { key }
}

// MARK: - Session Listing Protocol

protocol SessionListing: AnyObject {
    func listSessions(limit: Int, activeMinutes: Int?, includeDerivedTitles: Bool, includeLastMessage: Bool) async throws -> [GatewaySession]
}

// MARK: - ViewModel

@MainActor
final class SessionPickerViewModel: ObservableObject {
    @Published private(set) var sessions: [GatewaySession] = [GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main")]
    @Published private(set) var isLoading = false
    @Published var selectedSessionKey: String = "agent:main:main"

    private let sessionLister: SessionListing

    init(sessionLister: SessionListing) {
        self.sessionLister = sessionLister
    }

    func loadSessions() async {
        isLoading = true
        do {
            let result = try await sessionLister.listSessions(
                limit: 20,
                activeMinutes: nil,
                includeDerivedTitles: true,
                includeLastMessage: true
            )
            print("📋 [SESSION_PICKER] sessions.list returned \(result.count) sessions")
            for session in result {
                print("📋 [SESSION_PICKER]   key=\(session.key) title=\(session.title) channelType=\(session.channelType ?? "nil")")
            }
            // Filter: only keep agent:main: sessions that are main or Discord
            let filtered = result.filter { $0.key.hasPrefix("agent:main:") && ($0.key == "agent:main:main" || $0.key.contains(":discord:")) }
            print("📋 [SESSION_PICKER] after filter: \(filtered.count) sessions")
            // Clean up titles
            let cleaned = filtered.map { Self.cleanSessionTitle($0) }
            // Ensure agent:main:main is always present as fallback
            let mainFallback = GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main")
            var merged = cleaned
            if !merged.contains(where: { $0.key == "agent:main:main" }) {
                merged.insert(mainFallback, at: 0)
            }
            sessions = merged
        } catch {
            print("⚠️ [SESSION_PICKER] loadSessions failed: \(error)")
            // Keep existing sessions (including static fallback) on failure
        }
        // Auto-select: keep current selection if still valid, otherwise prefer agent:main:main, fallback to first
        if sessions.contains(where: { $0.key == selectedSessionKey }) {
            // Keep existing selection
        } else if sessions.contains(where: { $0.key == "agent:main:main" }) {
            selectedSessionKey = "agent:main:main"
        } else if let first = sessions.first {
            selectedSessionKey = first.key
        }
        isLoading = false
    }

    /// The session key to use for voice transcripts.
    var activeSessionKey: String {
        selectedSessionKey
    }

    /// Display title for the currently selected session.
    var selectedSessionTitle: String {
        if let session = sessions.first(where: { $0.key == selectedSessionKey }) {
            return session.title
        }
        return "Main"
    }

    /// Whether a session is selected and voice can start.
    var isSessionSelected: Bool {
        true
    }

    /// Clean up a session's title for display.
    /// - Main session always shows "Main" regardless of derived title.
    /// - Discord sessions extract the channel name after '#' (e.g. "discord:123#general" → "general").
    static func cleanSessionTitle(_ session: GatewaySession) -> GatewaySession {
        if session.key == "agent:main:main" {
            return GatewaySession(key: session.key, title: "Main", lastMessage: session.lastMessage, channelType: session.channelType)
        }
        if session.key.contains(":discord:"), let hashIndex = session.title.lastIndex(of: "#") {
            let channelName = String(session.title[session.title.index(after: hashIndex)...])
            if !channelName.isEmpty {
                return GatewaySession(key: session.key, title: channelName, lastMessage: session.lastMessage, channelType: session.channelType)
            }
        }
        return session
    }
}
