import Foundation
import Combine

@Observable
final class SettingsManager {

    static let shared = SettingsManager()

    // MARK: - UserDefaults Keys

    private enum Key: String {
        case webhookURL = "settings.webhookURL"  // legacy key, now stores hostname
        case authToken = "settings.authToken"
        case locationTrackingEnabled = "settings.locationTrackingEnabled"
        case sleepTrackingEnabled = "settings.sleepTrackingEnabled"
        case workoutTrackingEnabled = "settings.workoutTrackingEnabled"
        case activityTrackingEnabled = "settings.activityTrackingEnabled"
        case heartRateTrackingEnabled = "settings.heartRateTrackingEnabled"
        case ttsVoiceIdentifier = "settings.ttsVoiceIdentifier"
        case gatewayToken = "settings.gatewayToken"
        case useDevConfig = "settings.useDevConfig"
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

    /// AVSpeechSynthesisVoice identifier for TTS responses. Empty string = system default.
    var ttsVoiceIdentifier: String {
        didSet { defaults.set(ttsVoiceIdentifier, forKey: Key.ttsVoiceIdentifier.rawValue) }
    }

    /// Gateway WebSocket auth token (used for pairing/voice — separate from the hooks Bearer Token).
    var gatewayToken: String {
        didSet { defaults.set(gatewayToken, forKey: Key.gatewayToken.rawValue) }
    }

    /// Use development configuration (localhost) vs production (REDACTED_HOSTNAME).
    var useDevConfig: Bool {
        didSet { 
            defaults.set(useDevConfig, forKey: Key.useDevConfig.rawValue)
            // Note: No longer auto-applies config - user sets hostname manually in Settings
        }
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
        self.ttsVoiceIdentifier = defaults.string(forKey: Key.ttsVoiceIdentifier.rawValue) ?? ""
        self.gatewayToken = defaults.string(forKey: Key.gatewayToken.rawValue) ?? ""
        
        #if targetEnvironment(simulator)
        // Default to dev config in simulator
        self.useDevConfig = defaults.object(forKey: Key.useDevConfig.rawValue) as? Bool ?? true
        #else
        // Default to production config on real devices
        self.useDevConfig = defaults.bool(forKey: Key.useDevConfig.rawValue)
        #endif
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

    /// WebSocket URL for the voice gateway connection.
    /// Uses the same hostname as the webhook settings (ws:// for local, wss:// for remote).
    var voiceWebSocketURL: URL? {
        let h = hostname
        guard !h.isEmpty else { return nil }
        let scheme = isLocalHostname ? "ws" : "wss"
        return URL(string: "\(scheme)://\(h)")
    }

    /// True when minimum configuration is present (valid hostname + non-empty token).
    var isConfigured: Bool {
        webhookURLValue != nil && !authToken.isEmpty
    }

    // MARK: - Configuration Modes
    // Note: Removed auto-apply functionality - user manually configures hostname in Settings UI
}
