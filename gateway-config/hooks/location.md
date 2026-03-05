# Hook: Location Update

You received a JSON payload from Zaap. Append to today's memory (`memory/YYYY-MM-DD.md`) under `## Location`. Do NOT announce or reply.

## Payload Schema
- `latitude`: decimal degrees (Double)
- `longitude`: decimal degrees (Double)
- `altitude`: meters above sea level (Double)
- `speed`: meters/sec, -1 if unavailable (Double)
- `timestamp`: ISO 8601 datetime (use local HH:MM as TIMESTAMP)

## Memory Format
```
- TIMESTAMP — lat=LATITUDE, lng=LONGITUDE, alt=ALTITUDEm, speed=SPEEDm/s (via Zaap)
```

## Location-Triggered Reminders
After logging, check `AGENDA.md` for any items under a "Location-Triggered Reminders" section that are not yet delivered. If current coordinates are within ~0.5km of a pending reminder location (≈ 0.005° lat/lng), send it via iMessage to `micahmartin@mac.com` and mark it delivered in `AGENDA.md`.
