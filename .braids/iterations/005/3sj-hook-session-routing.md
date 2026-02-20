# Hook Session Routing Fix (zaap-3sj)

## Problem
Location webhooks used `action: "agent"` which created isolated hook sessions inaccessible from the main agent session. Location data couldn't be persisted to memory files.

## Fix
Changed the location hook in `~/.openclaw/openclaw.json`:
- `action`: `"agent"` → `"wake"` (injects into main session as a system event)
- Removed `agentId` and `deliver` fields (not applicable to wake action)
- Updated `messageTemplate` to include instructions for the agent to persist location data to daily memory files

## Verification
- Gateway restarted successfully
- Config confirmed: location hook now uses `action: "wake"`
