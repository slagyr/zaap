import Foundation
import Combine

@Observable
final class SettingsManager {

    static let shared = SettingsManager()

    // MARK: - UserDefaults Keys

    private enum Key: String {
        case webhookURL = "settings.webhookURL"
        case authToken = "settings.authToken"
        case locationTrackingEnabled = "settings.locationTrackingEnabled"
        case sleepTrackingEnabled = "settings.sleepTrackingEnabled"
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

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.webhookURL = defaults.string(forKey: Key.webhookURL.rawValue) ?? ""
        self.authToken = defaults.string(forKey: Key.authToken.rawValue) ?? ""
        self.locationTrackingEnabled = defaults.bool(forKey: Key.locationTrackingEnabled.rawValue)
        self.sleepTrackingEnabled = defaults.bool(forKey: Key.sleepTrackingEnabled.rawValue)
    }

    // MARK: - Convenience

    /// Returns the webhook URL as a valid URL, or nil if empty/invalid.
    var webhookURLValue: URL? {
        URL(string: webhookURL)
    }

    /// True when minimum configuration is present (valid URL + non-empty token).
    var isConfigured: Bool {
        webhookURLValue != nil && !authToken.isEmpty
    }
}
