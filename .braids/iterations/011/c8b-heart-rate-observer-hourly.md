# zaap-c8b: Change heart rate observer frequency from immediate to hourly

## Summary

The heart rate observer frequency was already changed from `.immediate` to `.hourly` in `HealthKitObserverService.swift` as part of a prior commit (08a3035). The corresponding test assertion in `HealthKitObserverServiceTests.swift` was also updated to expect `.hourly`.

## Changes

- `Zaap/Zaap/HealthKitObserverService.swift`: `frequency(for: .heartRate)` returns `.hourly`
- `Zaap/ZaapTests/HealthKitObserverServiceTests.swift`: test asserts `.hourly` for heart rate

## Notes

- Build currently has pre-existing compilation errors from the HRV/SpO2 work-in-progress (duplicate enum cases, missing types) — unrelated to this bead.
