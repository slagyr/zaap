# zaap-l1a: Dashboard Chart Legend & Bar Color Sync

## Problem

Legend colors did not consistently match bar colors in the grouped `Chart` on `DashboardView`.

### Root Cause

`transformToChartData(_:)` mapped over a Swift `Dictionary` (`[DeliveryGroupKey: [DeliveryRecord]]`), whose iteration order is non-deterministic. SwiftCharts assigns default color indices based on **first-appearance order** in the data array. With an unordered data source, the legend entries could appear in a different sequence on each render, visually mismatching the bar colors even though the `chartForegroundStyleScale` keys were spelled correctly.

Additionally, the chart legend was rendered in the default position (trailing), which can visually decouple it from the axis labels and bars.

## Diagnosis

| File | Observation |
|------|-------------|
| `DashboardViewModel.swift` — `transformToChartData` | Iterated `grouped.map { key, records in … }` with no sort; order is undefined at runtime. |
| `DashboardView.swift` — `chartForegroundStyleScale` | Keys match `displayName(for:)` output exactly, so color-by-key mapping is correct — but the *order* SwiftCharts sees them in the data is not guaranteed. |
| `displayName(for:)` | Correctly maps `.workout` → `"Workouts"` matching the scale key. No mismatch here. |

## Fix

### `DashboardViewModel.swift`

Added a canonical `seriesOrder` array and sorted the output of `transformToChartData` by that order (then by date within the same type):

```swift
static let seriesOrder: [DeliveryDataType] = [.location, .sleep, .heartRate, .activity, .workout]

static func transformToChartData(...) -> [ChartDataPoint] {
    ...
    .sorted { a, b in
        let ai = seriesOrder.firstIndex(of: a.dataType) ?? seriesOrder.count
        let bi = seriesOrder.firstIndex(of: b.dataType) ?? seriesOrder.count
        return ai != bi ? ai < bi : a.date < b.date
    }
}
```

This ensures SwiftCharts always encounters data types in the order: **Location → Sleep → Heart Rate → Activity → Workouts**, which matches the `chartForegroundStyleScale` key sequence.

### `DashboardView.swift`

Added explicit legend positioning so the legend renders at the bottom of the chart, left-aligned, keeping it visually adjacent to the bars:

```swift
.chartLegend(position: .bottom, alignment: .leading)
```

## Verification

```
xcodebuild build -project ~/Projects/zaap/Zaap/Zaap.xcodeproj \
  -scheme Zaap \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
# → ** BUILD SUCCEEDED **
```

## Files Changed

- `Zaap/Zaap/DashboardViewModel.swift` — added `seriesOrder` + stable sort in `transformToChartData`
- `Zaap/Zaap/DashboardView.swift` — added `.chartLegend(position: .bottom, alignment: .leading)`
