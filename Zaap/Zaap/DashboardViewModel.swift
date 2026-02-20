import Foundation
import SwiftUI

struct DashboardViewModel {

    struct ChartDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let dataType: DeliveryDataType
        let count: Int
    }

    static func color(for dataType: DeliveryDataType) -> Color {
        switch dataType {
        case .location: return .blue
        case .sleep: return .indigo
        case .heartRate: return .red
        case .activity: return .green
        case .workout: return .orange
        }
    }

    static func displayName(for dataType: DeliveryDataType) -> String {
        switch dataType {
        case .location: return "Location"
        case .sleep: return "Sleep"
        case .heartRate: return "Heart Rate"
        case .activity: return "Activity"
        case .workout: return "Workouts"
        }
    }

    /// Canonical order for chart series — must match chartForegroundStyleScale key order.
    static let seriesOrder: [DeliveryDataType] = [.location, .sleep, .heartRate, .activity, .workout]

    static func transformToChartData(_ grouped: [DeliveryGroupKey: [DeliveryRecord]]) -> [ChartDataPoint] {
        let calendar = Calendar.current
        return grouped.map { key, records in
            let date = calendar.date(from: key.day) ?? Date()
            return ChartDataPoint(date: date, dataType: key.dataType, count: records.count)
        }
        .sorted { a, b in
            let ai = seriesOrder.firstIndex(of: a.dataType) ?? seriesOrder.count
            let bi = seriesOrder.firstIndex(of: b.dataType) ?? seriesOrder.count
            return ai != bi ? ai < bi : a.date < b.date
        }
    }
}
