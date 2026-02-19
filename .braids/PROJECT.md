# Zaap

- **Status:** active
- **Priority:** normal
- **Autonomy:** full
- **Checkin:** on-demand
- **Channel:** 1472667753080160308
- **MaxWorkers:** 4
- **WorkerTimeout:** 3600

## Notifications

| Event | Notify |
|-------|--------|
| iteration-start | on |
| bead-start | on |
| bead-complete | on |
| iteration-complete | on (mention <@274692642116337664>) |
| no-ready-beads | on |
| question | on (mention <@274692642116337664>) |
| blocker | on (mention <@274692642116337664>) |

## Goal

Build a lightweight iOS app that securely relays personal telemetry — location, health/sleep data — to the OpenClaw gateway via webhooks. Zaap is Zane's sensory link to Micah's physical world. Privacy-first: the user controls exactly what data is shared, with no capabilities beyond what's explicitly built.

**Key features (in priority order):**
1. Significant location change monitoring (background) → POST to `/hooks/location`
2. HealthKit sleep data reading → POST to `/hooks/health` (morning summary)
3. Configurable webhook URL and auth token
4. Per-data-type enable/disable toggles

## Guardrails

- Swift/SwiftUI only, no third-party dependencies
- Minimal permissions — only request what's actively used (location, HealthKit)
- All data goes to the user-configured webhook endpoint only
- No analytics, no tracking, no third-party SDKs
- User must explicitly enable each data type before it activates
- No camera, microphone, contacts, or calendar access — keep scope tight
- Must work on iOS 17+
