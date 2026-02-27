# WorkoutReader: clarify noData error message (zaap-d1o)

## Summary

The `WorkoutReader.WorkoutError.noData` error message already reads **"No workouts found in the last 24 hours"** — the vague message described in the bead does not exist in the codebase.

## Verification

- `WorkoutReader.swift:30` — error message is `"No workouts found in the last 24 hours"`
- `WorkoutReaderTests.swift:29-30` — test asserts this exact string
- Full test suite passes (`TEST SUCCEEDED`)

## Notes

- Other readers (HeartRateReader, SleepDataReader, ActivityReader) still use the vaguer "for the requested period" phrasing. Could be clarified in separate beads if desired.
