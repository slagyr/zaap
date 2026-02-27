import SwiftUI
import Charts
import SwiftData

struct DashboardView: View {
    @Query(sort: [SortDescriptor(\DeliveryRecord.timestamp, order: .reverse)])
    private var records: [DeliveryRecord]

    private var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var sevenDaysAgo: Date {
        Calendar.current.date(byAdding: .day, value: -6, to: startOfToday)!
    }

    private var endOfToday: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)!
    }

    private var chartData: [DashboardViewModel.ChartDataPoint] {
        let calendar = Calendar.current
        var grouped: [DeliveryGroupKey: [DeliveryRecord]] = [:]
        for record in records where record.timestamp >= sevenDaysAgo {
            let components = calendar.dateComponents([.year, .month, .day], from: record.timestamp)
            let key = DeliveryGroupKey(dataType: record.dataType, day: components)
            grouped[key, default: []].append(record)
        }
        return DashboardViewModel.transformToChartData(grouped)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deliveries (7 Days)")
                .font(.headline)
                .padding(.horizontal)

            if chartData.isEmpty {
                ContentUnavailableView("No Deliveries", systemImage: "chart.bar", description: Text("No delivery data for the past 7 days."))
            } else {
                Chart(chartData) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Count", point.count)
                    )
                    .foregroundStyle(by: .value("Type", DashboardViewModel.displayName(for: point.dataType)))
                    .position(by: .value("Type", DashboardViewModel.displayName(for: point.dataType)))
                }
                .chartForegroundStyleScale([
                    "Location": Color.blue,
                    "Sleep": Color.indigo,
                    "Heart Rate": Color.red,
                    "Activity": Color.green,
                    "Workouts": Color.orange,
                ])
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXScale(domain: sevenDaysAgo...endOfToday)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 1)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.primary.opacity(0.3))
                        AxisTick()
                            .foregroundStyle(Color.primary.opacity(0.3))
                        AxisValueLabel()
                    }
                }
                .frame(height: 250)
                .padding(.horizontal)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
