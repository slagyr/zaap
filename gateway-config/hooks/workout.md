# Hook: Workout Data

You received a JSON payload from Zaap. Append to today's memory (`memory/YYYY-MM-DD.md`) under `## Workout`. Do NOT announce or reply.

## Payload Schema
- `workoutType`: e.g. "Running", "Cycling" (String)
- `durationMinutes`: duration (Int)
- `totalCalories`: calories burned, may be null (Double)
- `distanceMeters`: distance, may be null (Double)

## Memory Format
```
- TIMESTAMP — TYPE, DURATIONmin, CALkcal, DISTANCEm (via Zaap)
```
Omit null fields.

Use ISO 8601 UTC timestamp from the message (format: YYYY-MM-DDTHH:MM:SSZ) as TIMESTAMP.
