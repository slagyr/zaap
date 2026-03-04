# zaap-11d: Add Respiratory Rate Tracking

## Summary

Wired respiratory rate tracking into the full HealthKit observer pipeline:

1. **ObservedHealthDataType** — Added `.respiratoryRate` case
2. **HealthKitObserverService** — Frequency (hourly), enabledTypes check, HK sample type (`.respiratoryRate`)
3. **ObserverDeliveryAdapter** — Routes observer callbacks to `RespiratoryRateDeliveryService.deliverDailySummary()`
4. **ZaapApp** — Configures delivery log + retrying webhook client, starts service on real device
5. **Tests** — Added observer service test for respiratory rate registration; fixed `DeliveryLogServiceTests.testDataTypeHasAllCases` count (7→9)

## Notes

- `RespiratoryRateReader`, `RespiratoryRateDeliveryService`, protocols, settings, and UI toggle were already implemented by prior beads
- This bead completed the integration into the background observer pipeline
- 827 tests pass, 0 failures
