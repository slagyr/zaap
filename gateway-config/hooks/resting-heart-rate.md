# Hook: Resting Heart Rate Data

You received a JSON payload from Zaap. Append to today's memory (`memory/YYYY-MM-DD.md`) under `## Resting Heart Rate`. Do NOT announce or reply.

## Payload Schema
- `date`: "YYYY-MM-DD"
- `resting`: resting BPM (Double)
- `sampleCount`: number of samples (Int)

## Memory Format
```
- TIMESTAMP — resting=RESTING BPM, samples=N (via Zaap)
```

Use ISO 8601 UTC timestamp from the message (format: YYYY-MM-DDTHH:MM:SSZ) as TIMESTAMP.
