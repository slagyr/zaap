import SwiftUI
import Charts
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var chartData: [DashboardViewModel.ChartDataPoint] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deliveries (7 Days)")
                .font(.headline)
                .padding(.horizontal)

            if chartData.isEmpty && errorMessage == nil {
                ContentUnavailableView("No Deliveries", systemImage: "chart.bar", description: Text("No delivery data for the past 7 days."))
            } else if let error = errorMessage {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
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
        .onAppear { loadData() }
    }

    private func loadData() {
        let service = DeliveryLogService(context: modelContext)
        do {
            let grouped = try service.recordsGroupedByTypeAndDay(lastDays: 7)
            chartData = DashboardViewModel.transformToChartData(grouped)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
