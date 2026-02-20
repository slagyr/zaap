# zaap-fc0 — Fix Dashboard X-axis to Always Show 7 Days

## Summary

Fixed `DashboardView.swift` so the bar chart always renders a full 7-day X-axis, regardless of whether data exists for every day.

## Changes

**File:** `Zaap/Zaap/DashboardView.swift`

### Added computed date properties

```swift
private var startOfToday: Date {
    Calendar.current.startOfDay(for: Date())
}

private var sevenDaysAgo: Date {
    Calendar.current.date(byAdding: .day, value: -6, to: startOfToday)!
}

private var endOfToday: Date {
    Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)!
}
```

### Added chart modifiers

```swift
.chartXScale(domain: sevenDaysAgo...endOfToday)
.chartXAxis {
    AxisMarks(values: .stride(by: .day, count: 1)) { value in
        AxisGridLine()
        AxisTick()
        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
    }
}
```

## Result

- X-axis always spans exactly 7 days (today − 6 days through end of today)
- Each day shows its weekday abbreviation (Mon, Tue, Wed, etc.)
- Days with no data render as empty columns rather than being omitted

## Build

`** BUILD SUCCEEDED **` — xcodebuild for iPhone 17 Pro simulator
