import Foundation

/// Persists last-delivered timestamps per data type so delivery services
/// can skip redundant sends.
protocol DeliveryAnchorStoring {
    func lastDelivered(for dataType: DeliveryDataType) -> Date?
    func setLastDelivered(_ date: Date, for dataType: DeliveryDataType)
}

/// Stores delivery anchors in UserDefaults.
final class UserDefaultsDeliveryAnchorStore: DeliveryAnchorStoring {

    private let defaults: UserDefaults
    private static let keyPrefix = "DeliveryAnchor_"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastDelivered(for dataType: DeliveryDataType) -> Date? {
        let interval = defaults.double(forKey: Self.keyPrefix + dataType.rawValue)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    func setLastDelivered(_ date: Date, for dataType: DeliveryDataType) {
        defaults.set(date.timeIntervalSince1970, forKey: Self.keyPrefix + dataType.rawValue)
    }
}

/// Null implementation that never deduplicates.
final class NullDeliveryAnchorStore: DeliveryAnchorStoring {
    func lastDelivered(for dataType: DeliveryDataType) -> Date? { nil }
    func setLastDelivered(_ date: Date, for dataType: DeliveryDataType) {}
}
