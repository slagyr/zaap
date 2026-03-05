# Hook: Daily Health Check-In

You are doing Micah's daily 9 AM health review. Follow these steps exactly.

## 1. Gather Data

Read the memory files for today and yesterday:
- `~/.openclaw/workspace/memory/YYYY-MM-DD.md` (today)
- `~/.openclaw/workspace/memory/YYYY-MM-DD.md` (yesterday)

Look for sections: `## Sleep`, `## Heart Rate`, `## Activity`, `## Workout`, `## Location`

## 2. Check for Data Gap

If there is NO health data (sleep, HR, activity, or workout) in the last 24 hours, send this alert via iMessage and stop:

> "⚠️ Zane here — I haven't received any health data from Zaap in over 24 hours. You may want to check the app is running and the hook token is correct."

## 3. Analyze the Data

Look at what's available and assess:

**Sleep:**
- Total sleep < 6 hours = concerning
- Deep sleep < 10% of total = note it
- REM < 15% of total = note it
- Awake time > 60 min = note it

**Heart Rate:**
- Resting HR > 75 = worth noting
- Resting HR > 85 = concerning

**Activity:**
- Steps < 3000 = sedentary day
- Active energy < 200 kcal = sedentary day

**Workout:**
- Note any workouts logged

**Location:**
- If airborne data detected (speed > 30 m/s at altitude), note the flight

## 4. Send iMessage Summary

Send to `micahmartin@mac.com` via iMessage. Keep it concise — 3-5 lines max. Lead with anything concerning, otherwise keep it positive and brief.

Format example:
```
🦊 Morning health check:
😴 Sleep: 7h 12m (good — solid REM)
❤️ Resting HR: 58 bpm
🏃 Activity: 8,432 steps
All looks good. Have a great day!
```

If something is concerning, flag it clearly:
```
🦊 Morning health check:
⚠️ Sleep was only 4h 20m last night — you may want to take it easy today.
❤️ Resting HR: 72 bpm (slightly elevated)
🏃 Activity: 2,100 steps
```

## 5. Do NOT reply to Discord

This runs as a silent background job. Use iMessage only. Do not post to any Discord channel.
