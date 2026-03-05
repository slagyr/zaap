# Hook: Respiratory Rate Data

You received a JSON payload from Zaap. Append to today's memory (`memory/YYYY-MM-DD.md`) under `## Respiratory Rate`. Do NOT announce or reply.

## Payload Schema
- `date`: "YYYY-MM-DD"
- `min`: lowest breaths/min (Double)
- `max`: highest breaths/min (Double)
- `avg`: average breaths/min (Double)
- `sampleCount`: number of samples (Int)

## Memory Format
```
- TIMESTAMP — avg=AVG min=MIN max=MAX breaths/min, samples=N (via Zaap)
```

Use the local time (HH:MM, America/Phoenix) as TIMESTAMP.
