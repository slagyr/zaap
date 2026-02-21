import Foundation
import Combine

@Observable
final class SettingsManager {

    static let shared = SettingsManager()

    // MARK: - UserDefaults Keys

    private enum Key: String {
        case webhookURL = "settings.webhookURL"  // legacy key, now stores hostname
        case authToken = "settings.authToken"
        case voiceGatewayHostname = "settings.voiceGatewayHostname"
        case locationTrackingEnabled = "settings.locationTrackingEnabled"
        case sleepTrackingEnabled = "settings.sleepTrackingEnabled"
        case workoutTrackingEnabled = "settings.workoutTrackingEnabled"
        case activityTrackingEnabled = "settings.activityTrackingEnabled"
        case heartRateTrackingEnabled = "settings.heartRateTrackingEnabled"
    }

    private let defaults: UserDefaults

    // MARK: - Published Settings

    var webhookURL: String {
        didSet { defaults.set(webhookURL, forKey: Key.webhookURL.rawValue) }
    }

    var authToken: String {
        didSet { defaults.set(authToken, forKey: Key.authToken.rawValue) }
    }

    var locationTrackingEnabled: Bool {
        didSet { defaults.set(locationTrackingEnabled, forKey: Key.locationTrackingEnabled.rawValue) }
    }

    var sleepTrackingEnabled: Bool {
        didSet { defaults.set(sleepTrackingEnabled, forKey: Key.sleepTrackingEnabled.rawValue) }
    }

    var workoutTrackingEnabled: Bool {
        didSet { defaults.set(workoutTrackingEnabled, forKey: Key.workoutTrackingEnabled.rawValue) }
    }

    var activityTrackingEnabled: Bool {
        didSet { defaults.set(activityTrackingEnabled, forKey: Key.activityTrackingEnabled.rawValue) }
    }

    var heartRateTrackingEnabled: Bool {
        didSet { defaults.set(heartRateTrackingEnabled, forKey: Key.heartRateTrackingEnabled.rawValue) }
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.webhookURL = defaults.string(forKey: Key.webhookURL.rawValue) ?? ""
        self.authToken = defaults.string(forKey: Key.authToken.rawValue) ?? ""
        self.locationTrackingEnabled = defaults.bool(forKey: Key.locationTrackingEnabled.rawValue)
        self.sleepTrackingEnabled = defaults.bool(forKey: Key.sleepTrackingEnabled.rawValue)
        self.workoutTrackingEnabled = defaults.bool(forKey: Key.workoutTrackingEnabled.rawValue)
        self.activityTrackingEnabled = defaults.bool(forKey: Key.activityTrackingEnabled.rawValue)
        self.heartRateTrackingEnabled = defaults.bool(forKey: Key.heartRateTrackingEnabled.rawValue)
    }

    // MARK: - Convenience

    /// The cleaned hostname (strips protocol, trailing slashes, paths).
    var hostname: String {
        var h = webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip protocol if user pastes a full URL
        if h.lowercased().hasPrefix("https://") { h = String(h.dropFirst(8)) }
        if h.lowercased().hasPrefix("http://") { h = String(h.dropFirst(7)) }
        // Strip trailing slashes and paths
        if let slashIndex = h.firstIndex(of: "/") { h = String(h[..<slashIndex]) }
        return h
    }

    /// True when the hostname refers to a local/dev server (uses http instead of https).
    var isLocalHostname: Bool {
        let h = hostname.lowercased()
        let bare = h.components(separatedBy: ":").first ?? h
        return bare == "localhost" || bare == "127.0.0.1" || bare.hasSuffix(".local")
    }

    /// Returns the base webhook URL built from the hostname, or nil if empty.
    var webhookURLValue: URL? {
        let h = hostname
        guard !h.isEmpty else { return nil }
        let scheme = isLocalHostname ? "http" : "https"
        return URL(string: "\(scheme)://\(h)/hooks")
    }

    /// Build a full URL for a specific service path (e.g. "/location").
    func serviceURL(path: String) -> URL? {
        webhookURLValue?.appending(path: path)
    }

    /// Hostname used exclusively for voice/WebSocket gateway connections.
    /// Stored separately so it is never overwritten by the dev/prod webhook toggle.
    /// Defaults to the webhook hostname when first set.
    var voiceGatewayHostname: String {
        get { defaults.string(forKey: Key.voiceGatewayHostname.rawValue) ?? hostname }
        set { defaults.set(newValue, forKey: Key.voiceGatewayHostname.rawValue) }
    }

    /// WebSocket URL for the voice gateway connection (ws:// for local, wss:// for remote).
    /// Always derived from voiceGatewayHostname, not the webhook URL.
    var voiceWebSocketURL: URL? {
        let h = voiceGatewayHostname
        guard !h.isEmpty else { return nil }
        let bare = h.components(separatedBy: ":").first ?? h
        let isLocal = bare == "localhost" || bare == "127.0.0.1" || bare.hasSuffix(".local")
        let scheme = isLocal ? "ws" : "wss"
        return URL(string: "\(scheme)://\(h)")
    }

    /// True when minimum configuration is present (valid hostname + non-empty token).
    var isConfigured: Bool {
        webhookURLValue != nil && !authToken.isEmpty
    }
}
