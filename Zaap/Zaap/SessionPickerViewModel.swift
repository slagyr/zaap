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
    func listSessions(limit: Int?, activeMinutes: Int?, includeDerivedTitles: Bool, includeLastMessage: Bool) async throws -> [GatewaySession]
}

// MARK: - Session Preview

struct PreviewMessage: Equatable {
    let role: String
    let text: String
}

protocol SessionPreviewing: AnyObject {
    func previewSession(key: String, limit: Int) async throws -> [PreviewMessage]
}

// MARK: - ViewModel

@MainActor
final class SessionPickerViewModel: ObservableObject {
    @Published private(set) var sessions: [GatewaySession] = [GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main")]
    @Published private(set) var isLoading = false
    @Published var selectedSessionKey: String = "agent:main:main"
    @Published private(set) var previewMessages: [ConversationEntry] = []

    private let sessionLister: SessionListing
    private let sessionPreviewer: SessionPreviewing?

    init(sessionLister: SessionListing, sessionPreviewer: SessionPreviewing? = nil) {
        self.sessionLister = sessionLister
        self.sessionPreviewer = sessionPreviewer
    }

    func loadSessions() async {
        isLoading = true
        do {
            let result = try await sessionLister.listSessions(
                limit: nil,
                activeMinutes: nil,
                includeDerivedTitles: true,
                includeLastMessage: false
            )
            print("📋 [SESSION_PICKER] sessions.list returned \(result.count) sessions")
            for session in result {
                print("📋 [SESSION_PICKER]   key=\(session.key) title=\(session.title) channelType=\(session.channelType ?? "nil")")
            }
            // Filter: only keep agent:main: sessions that are main or Discord
            let filtered = result.filter { $0.key.hasPrefix("agent:main:") && ($0.key == "agent:main:main" || $0.key.contains(":discord:")) }
            print("📋 [SESSION_PICKER] after filter: \(filtered.count) sessions")
            // Clean up titles, then drop discord sessions with no resolved channel name
            let cleaned = filtered.map { Self.cleanSessionTitle($0) }
                .filter { !($0.key.contains(":discord:") && $0.title.hasPrefix("discord:")) }
            // Ensure agent:main:main is always present as fallback
            let mainFallback = GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main")
            var merged = cleaned
            if !merged.contains(where: { $0.key == "agent:main:main" }) {
                merged.insert(mainFallback, at: 0)
            }
            // Sort: Main first, then reverse-alphabetical by title
            // (Menu/Picker renders bottom-to-top, so descending here = A-Z on screen)
            sessions = merged.sorted { a, b in
                if a.key == "agent:main:main" { return true }
                if b.key == "agent:main:main" { return false }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedDescending
            }
        } catch {
            print("⚠️ [SESSION_PICKER] loadSessions failed: \(error)")
            // Keep existing sessions (including static fallback) on failure
        }
        // Auto-select: keep current selection if still valid, otherwise prefer #general, fallback to Main, then first
        if sessions.contains(where: { $0.key == selectedSessionKey }) {
            // Keep existing selection — but if it's the initial default (Main) and #general is available, switch
            if selectedSessionKey == "agent:main:main",
               let general = sessions.first(where: { $0.title.lowercased() == "general" }) {
                selectedSessionKey = general.key
            }
        } else if let general = sessions.first(where: { $0.title.lowercased() == "general" }) {
            selectedSessionKey = general.key
        } else if sessions.contains(where: { $0.key == "agent:main:main" }) {
            selectedSessionKey = "agent:main:main"
        } else if let first = sessions.first {
            selectedSessionKey = first.key
        }
        isLoading = false
        // Auto-load preview for the selected session
        await loadPreview(forSession: selectedSessionKey)
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

    /// Fetch recent messages for a session and publish them as preview.
    func loadPreview(forSession key: String) async {
        guard let previewer = sessionPreviewer else { return }
        do {
            let messages = try await previewer.previewSession(key: key, limit: 10)
            previewMessages = messages.compactMap { msg in
                switch msg.role {
                case "user":
                    let cleaned = Self.cleanPreviewText(msg.text)
                    guard let text = cleaned else { return nil }
                    return ConversationEntry(role: .user, text: text)
                case "assistant":
                    return ConversationEntry(role: .agent, text: msg.text)
                default:
                    return nil
                }
            }
        } catch {
            previewMessages = []
        }
    }

    /// Clean preview text by filtering system-injected messages and stripping metadata preambles.
    /// Returns nil if the message should be filtered out entirely.
    static func cleanPreviewText(_ text: String) -> String? {
        if text.hasPrefix("System: [") { return nil }
        if text.hasPrefix("Read HEARTBEAT.md") { return nil }
        if text.hasPrefix("[System Message]") { return nil }

        let result = stripMetadataPreambles(text)
        return result.isEmpty ? nil : result
    }

    /// Strip gateway-injected metadata preamble blocks from message text.
    /// Blocks look like: `Label (untrusted metadata):\n```json\n{...}\n```\n\n`
    /// There may be multiple (e.g. "Conversation info" followed by "Sender").
    private static func stripMetadataPreambles(_ text: String) -> String {
        var remaining = text
        let metadataSuffix = " (untrusted metadata):"
        while remaining.contains(metadataSuffix),
              let labelEnd = remaining.range(of: metadataSuffix) {
            let beforeLabel = remaining[..<labelEnd.lowerBound]
            let isAtStart = !beforeLabel.contains("\n")
            guard isAtStart else { break }

            // Find the opening ``` fence (e.g. ```json)
            let searchStart = labelEnd.upperBound
            guard let openFence = remaining.range(of: "```", range: searchStart..<remaining.endIndex) else {
                return ""
            }
            // Find the closing ``` fence after the opening one
            let afterOpen = openFence.upperBound
            guard let closeFence = remaining.range(of: "```", range: afterOpen..<remaining.endIndex) else {
                return ""
            }
            remaining = String(remaining[closeFence.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return remaining
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
