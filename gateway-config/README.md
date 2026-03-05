# Zaap Gateway Configuration

Files needed to configure OpenClaw gateway for Zaap telemetry ingestion.

## Setup

1. Copy `hooks/*.md` files to `~/.openclaw/workspace/hooks/`
2. Merge `hooks-config.json` → `hooks` section into `~/.openclaw/openclaw.json`
3. Restart gateway: `openclaw gateway restart`

## Hook Files

Each `.md` file tells the agent how to parse and store the incoming webhook payload:

| File | Data type | Memory section |
|------|-----------|---------------|
| `heartrate.md` | Heart rate (min/max/avg BPM) | `## Heart Rate` |
| `hrv.md` | Heart rate variability (SDNN ms) | `## HRV` |
| `spo2.md` | Blood oxygen % | `## SpO2` |
| `respiratory-rate.md` | Breaths per minute | `## Respiratory Rate` |
| `resting-heart-rate.md` | Resting BPM | `## Resting Heart Rate` |
| `activity.md` | Steps, distance, calories | `## Activity` |
| `sleep.md` | Sleep stages (deep/REM/core) | `## Sleep` |
| `workout.md` | Workout sessions | `## Workout` |
| `location.md` | GPS coordinates | `## Location` |
