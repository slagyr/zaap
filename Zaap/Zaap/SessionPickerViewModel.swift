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
    @Published private(set) var sessions: [GatewaySession] = []
    @Published private(set) var isLoading = false
    @Published var selectedSessionKey: String? = nil

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
            sessions = result.filter { $0.channelType == "discord" }
        } catch {
            sessions = []
        }
        // Auto-select: keep current selection if still valid, otherwise pick first
        if let selected = selectedSessionKey, sessions.contains(where: { $0.key == selected }) {
            // Keep existing selection
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

    /// Whether a session is selected and voice can start.
    var isSessionSelected: Bool {
        selectedSessionKey != nil
    }
}
