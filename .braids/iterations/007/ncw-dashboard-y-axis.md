# zaap-ncw: Add Y-axis scale to Dashboard delivery chart

## Summary

Added a labeled Y-axis to the Swift Charts bar chart in `DashboardView.swift` so users can read exact delivery counts without guessing.

## Changes

**File:** `Zaap/Zaap/DashboardView.swift`

Added `.chartYAxis` modifier to the `Chart` view:

```swift
.chartYAxis {
    AxisMarks(position: .leading) { value in
        AxisGridLine()
            .foregroundStyle(Color.primary.opacity(0.3))
        AxisTick()
            .foregroundStyle(Color.primary.opacity(0.3))
        AxisValueLabel()
    }
}
```

## Features

- **Labeled tick marks** — integer count labels on the leading edge
- **Subtle gridlines** — `Color.primary` at 0.3 opacity (adapts to light/dark mode)
- **Auto-scaling** — Swift Charts infers the Y domain from data max automatically; no manual range needed
- **Leading position** — labels on the left side, standard iOS chart convention

## Build

`xcodebuild` — **BUILD SUCCEEDED** (iPhone 17 Pro simulator)
