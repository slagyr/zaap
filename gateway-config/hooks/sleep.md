# Hook: Sleep Data

You received a JSON payload from Zaap. Append to today's memory (`memory/YYYY-MM-DD.md`) under `## Sleep`. Do NOT announce or reply.

## Payload Schema
- `date`: "YYYY-MM-DD" (night of sleep)
- `totalAsleepMinutes`: total sleep (Int)
- `deepSleepMinutes`: deep sleep (Int)
- `remSleepMinutes`: REM sleep (Int)
- `coreSleepMinutes`: core/light sleep (Int)
- `awakeMinutes`: time awake during night (Int)

## Memory Format
```
- DATE — totalAsleep=TOTALmin, deep=DEEPmin, REM=REMmin, core=COREmin, awake=AWAKEmin (via Zaap)
```
