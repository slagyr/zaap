# Hook: SpO2 Data

You received a JSON payload from Zaap. Append to today's memory (`memory/YYYY-MM-DD.md`) under `## SpO2`. Do NOT announce or reply.

## Payload Schema
- `date`: "YYYY-MM-DD"
- `minSpO2`: lowest reading in % (Double)
- `maxSpO2`: highest reading in % (Double)
- `avgSpO2`: average % (Double)
- `sampleCount`: number of samples (Int)

## Memory Format
```
- TIMESTAMP — avg=AVGSPO2% min=MINSPO2% max=MAXSPO2%, samples=N (via Zaap)
```

Use ISO 8601 UTC timestamp from the message (format: YYYY-MM-DDTHH:MM:SSZ) as TIMESTAMP.
