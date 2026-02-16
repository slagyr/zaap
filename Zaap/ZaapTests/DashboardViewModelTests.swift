import XCTest
@testable import Zaap

final class DashboardViewModelTests: XCTestCase {

    // MARK: - Chart Data Point structure

    func testChartDataPointHasExpectedProperties() {
        let date = Date()
        let point = DashboardViewModel.ChartDataPoint(
            date: date,
            dataType: .location,
            count: 5
        )
        XCTAssertEqual(point.date, date)
        XCTAssertEqual(point.dataType, .location)
        XCTAssertEqual(point.count, 5)
    }

    // MARK: - Color mapping

    func testColorForLocation() {
        XCTAssertEqual(DashboardViewModel.color(for: .location), .blue)
    }

    func testColorForSleep() {
        XCTAssertEqual(DashboardViewModel.color(for: .sleep), .indigo)
    }

    func testColorForHeartRate() {
        XCTAssertEqual(DashboardViewModel.color(for: .heartRate), .red)
    }

    func testColorForActivity() {
        XCTAssertEqual(DashboardViewModel.color(for: .activity), .green)
    }

    func testColorForWorkout() {
        XCTAssertEqual(DashboardViewModel.color(for: .workout), .orange)
    }

    // MARK: - Data transformation

    func testTransformEmptyGroupedData() {
        let result = DashboardViewModel.transformToChartData([:])
        XCTAssertTrue(result.isEmpty)
    }

    func testTransformSingleGroupIntoChartDataPoint() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let components = calendar.dateComponents([.year, .month, .day], from: today)
        let key = DeliveryGroupKey(dataType: .location, day: components)
        let records = [
            DeliveryRecord(dataType: .location, timestamp: today, success: true),
            DeliveryRecord(dataType: .location, timestamp: today, success: true),
            DeliveryRecord(dataType: .location, timestamp: today, success: false),
        ]

        let result = DashboardViewModel.transformToChartData([key: records])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].dataType, .location)
        XCTAssertEqual(result[0].count, 3) // all records, not just successful
        XCTAssertEqual(result[0].date, today)
    }

    func testTransformMultipleTypesAndDays() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let todayComponents = calendar.dateComponents([.year, .month, .day], from: today)
        let yesterdayComponents = calendar.dateComponents([.year, .month, .day], from: yesterday)

        let grouped: [DeliveryGroupKey: [DeliveryRecord]] = [
            DeliveryGroupKey(dataType: .location, day: todayComponents): [
                DeliveryRecord(dataType: .location, timestamp: today, success: true),
            ],
            DeliveryGroupKey(dataType: .sleep, day: todayComponents): [
                DeliveryRecord(dataType: .sleep, timestamp: today, success: true),
                DeliveryRecord(dataType: .sleep, timestamp: today, success: true),
            ],
            DeliveryGroupKey(dataType: .heartRate, day: yesterdayComponents): [
                DeliveryRecord(dataType: .heartRate, timestamp: yesterday, success: true),
            ],
        ]

        let result = DashboardViewModel.transformToChartData(grouped)

        XCTAssertEqual(result.count, 3)

        let locationToday = result.first { $0.dataType == .location && $0.date == today }
        XCTAssertEqual(locationToday?.count, 1)

        let sleepToday = result.first { $0.dataType == .sleep && $0.date == today }
        XCTAssertEqual(sleepToday?.count, 2)

        let heartRateYesterday = result.first { $0.dataType == .heartRate && $0.date == yesterday }
        XCTAssertEqual(heartRateYesterday?.count, 1)
    }

    // MARK: - Display name

    func testDisplayNameForDataTypes() {
        XCTAssertEqual(DashboardViewModel.displayName(for: .location), "Location")
        XCTAssertEqual(DashboardViewModel.displayName(for: .sleep), "Sleep")
        XCTAssertEqual(DashboardViewModel.displayName(for: .heartRate), "Heart Rate")
        XCTAssertEqual(DashboardViewModel.displayName(for: .activity), "Activity")
        XCTAssertEqual(DashboardViewModel.displayName(for: .workout), "Workouts")
    }
}
