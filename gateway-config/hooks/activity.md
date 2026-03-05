# Hook: Activity Data

You received a JSON payload from Zaap. Append to today's memory (`memory/YYYY-MM-DD.md`) under `## Activity`. Do NOT announce or reply.

## Payload Schema
- `steps`: step count (Int)
- `distanceMeters`: distance walked/run in meters (Double)
- `activeEnergyKcal`: active calories burned (Double)
- `timestamp`: ISO 8601 datetime (use local HH:MM as TIMESTAMP)

## Memory Format
```
- TIMESTAMP — steps=STEPS, distance=DISTANCEm, activeEnergy=ENERGYkcal (via Zaap)
```
