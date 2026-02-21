import Foundation
import SwiftData

protocol DeliveryLogging {
    func record(dataType: DeliveryDataType, timestamp: Date, success: Bool, errorMessage: String?)
}

/// No-op implementation used as default when no log is injected.
struct NullDeliveryLog: DeliveryLogging {
    func record(dataType: DeliveryDataType, timestamp: Date, success: Bool, errorMessage: String?) {}
}

struct DeliveryGroupKey: Hashable {
    let dataType: DeliveryDataType
    let day: DateComponents // year, month, day
}

class DeliveryLogService: DeliveryLogging {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func record(dataType: DeliveryDataType, timestamp: Date, success: Bool, errorMessage: String? = nil) {
        let record = DeliveryRecord(dataType: dataType, timestamp: timestamp, success: success, errorMessage: errorMessage)
        context.insert(record)
        try? context.save()
    }

    func recordsGroupedByTypeAndDay(lastDays: Int) throws -> [DeliveryGroupKey: [DeliveryRecord]] {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -(lastDays), to: Date()) else {
            return [:]
        }
        let cutoff = calendar.startOfDay(for: cutoffDate)

        var descriptor = FetchDescriptor<DeliveryRecord>(
            predicate: #Predicate<DeliveryRecord> { record in
                record.timestamp >= cutoff
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        let records = try context.fetch(descriptor)

        var grouped: [DeliveryGroupKey: [DeliveryRecord]] = [:]
        for record in records {
            let components = calendar.dateComponents([.year, .month, .day], from: record.timestamp)
            let key = DeliveryGroupKey(dataType: record.dataType, day: components)
            grouped[key, default: []].append(record)
        }
        return grouped
    }
}
