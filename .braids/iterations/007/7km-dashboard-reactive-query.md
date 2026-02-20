# zaap-7km: Replace DashboardView onAppear with @Query for Live Reactive Updates

## Summary

Replaced the manual `loadData()` / `.onAppear` pattern in `DashboardView` with a SwiftData `@Query` property wrapper, giving the dashboard live, reactive updates whenever delivery records change.

## Changes

### `Zaap/DashboardView.swift` — full rewrite

**Removed:**
- `@Environment(\.modelContext)` (no longer needed for queries)
- `@State private var chartData: [DashboardViewModel.ChartDataPoint]`
- `@State private var errorMessage: String?`
- `loadData()` private method
- `.onAppear { loadData() }` modifier
- `DeliveryLogService` dependency

**Added:**
- `@Query(sort: [SortDescriptor(\DeliveryRecord.timestamp, order: .reverse)]) private var records: [DeliveryRecord]`
- `chartData` computed property that:
  - Filters `records` to those within the last 7 days (`>= sevenDaysAgo`)
  - Groups by `(dataType, day)` into `[DeliveryGroupKey: [DeliveryRecord]]`
  - Delegates transformation to the existing `DashboardViewModel.transformToChartData(_:)` static method

**Preserved:**
- All chart modifiers: `.chartXScale`, `.chartXAxis`, `.chartYAxis`, `.chartForegroundStyleScale`, `.chartLegend`
- `ContentUnavailableView` for empty state
- `sevenDaysAgo`, `endOfToday`, `startOfToday` computed date helpers

### `ZaapTests/DashboardViewModelTests.swift` — no changes needed

Tests cover `DashboardViewModel` static methods which were not modified.

## Why This Is Better

| Before | After |
|---|---|
| Data loaded once on appear | Data updates live as records are inserted |
| Manual `try`/`catch` error path | No error path — SwiftData manages fetching |
| Requires `ModelContext` for service calls | `@Query` handles fetch automatically |
| State drift if records change while view is visible | Always in sync with the store |

## Build Verification

```
** BUILD SUCCEEDED **
```

Scheme: `Zaap`, destination: `iPhone 17 Pro` (iOS Simulator)
