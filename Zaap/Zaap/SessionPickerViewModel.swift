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
    @Published var selectedSessionKey: String? = "agent:main:main"

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
            // Ensure agent:main:main is always present as fallback
            let mainFallback = GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main")
            var merged = result
            if !merged.contains(where: { $0.key == "agent:main:main" }) {
                merged.insert(mainFallback, at: 0)
            }
            sessions = merged
        } catch {
            // Keep existing sessions (including static fallback) on failure
        }
        // Auto-select: keep current selection if still valid, otherwise prefer agent:main:main, fallback to first
        if let selected = selectedSessionKey, sessions.contains(where: { $0.key == selected }) {
            // Keep existing selection
        } else if let mainSession = sessions.first(where: { $0.key == "agent:main:main" }) {
            selectedSessionKey = mainSession.key
        } else {
            selectedSessionKey = sessions.first?.key
        }
        isLoading = false
    }

    /// The session key to use for voice transcripts.
    /// Returns the selected key, or nil if no session is selected.
    var activeSessionKey: String? {
        selectedSessionKey
    }

    /// Display title for the currently selected session.
    var selectedSessionTitle: String {
        if let key = selectedSessionKey,
           let session = sessions.first(where: { $0.key == key }) {
            return session.title
        }
        return "New conversation"
    }

    /// Whether a session is selected and voice can start.
    var isSessionSelected: Bool {
        selectedSessionKey != nil
    }
}
