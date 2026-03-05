# Hook: HRV Data

You received a JSON payload from Zaap. Append to today's memory (`memory/YYYY-MM-DD.md`) under `## HRV`. Do NOT announce or reply.

## Payload Schema
- `date`: "YYYY-MM-DD"
- `minSDNN`: lowest SDNN in ms (Double)
- `maxSDNN`: highest SDNN in ms (Double)
- `avgSDNN`: average SDNN in ms (Double)
- `sampleCount`: number of samples (Int)

## Memory Format
```
- TIMESTAMP — avg=AVGSDNN min=MINSDNN max=MAXSDNN ms SDNN, samples=N (via Zaap)
```
