import Foundation
import SwiftData

enum DeliveryDataType: String, Codable, CaseIterable {
    case location
    case sleep
    case heartRate
    case activity
    case workout
}

@Model
final class DeliveryRecord {
    var dataType: DeliveryDataType
    var timestamp: Date
    var success: Bool
    var errorMessage: String?

    init(dataType: DeliveryDataType, timestamp: Date, success: Bool, errorMessage: String? = nil) {
        self.dataType = dataType
        self.timestamp = timestamp
        self.success = success
        self.errorMessage = errorMessage
    }
}
