# Hook: Heart Rate Data

You received a JSON payload from Zaap. Parse it and append to today's memory (`memory/YYYY-MM-DD.md`) under `## Heart Rate`. Do NOT announce or reply.

## Payload Schema
- `date`: "YYYY-MM-DD"
- `minBPM`: lowest BPM recorded (Double)
- `maxBPM`: highest BPM recorded (Double)
- `avgBPM`: average BPM (Double)
- `restingBPM`: resting heart rate, may be null (Double)
- `sampleCount`: number of samples (Int)

## Memory Format
Append exactly this line, substituting values from the payload. Use ISO 8601 UTC timestamp from the message (format: YYYY-MM-DDTHH:MM:SSZ):
```
- TIMESTAMP — min=MINBPM max=MAXBPM avg=AVGBPM resting=RESTINGBPM BPM, samples=N (via Zaap)
```
If `restingBPM` is null or missing, omit the resting field entirely.
