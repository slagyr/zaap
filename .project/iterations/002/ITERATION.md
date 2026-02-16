# Iteration 002

- **Status:** active

## Stories
- zaap-1b3: Sleep webhook delivery — wire SleepDataReader to WebhookClient POST
- zaap-q2l: Heart rate reader + delivery — read HR samples from HealthKit and POST
- zaap-16z: Step count & activity reader + delivery — daily steps, distance, active energy
- zaap-l6r: Workout session reader + delivery — read completed workouts and POST

## Guardrails
- Each reader must request only its specific HealthKit permissions
- Follow existing patterns: @Observable reader class + delivery service wiring
- All files must be added to Xcode project build sources (pbxproj) — lesson from iteration 001
- POST payloads should be self-describing (include data type, timestamp, units)
- Add toggles to SettingsView for each new data source
- Commit and push after each story

## Notes
- SleepDataReader already exists from iteration 001 — zaap-1b3 just wires it to WebhookClient
- WebhookClient and SettingsManager patterns are established — follow them
- HealthKit entitlements already configured
