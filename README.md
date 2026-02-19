# Zaap ⚡

Personal telemetry relay for iOS. Zaap reads health and location data from your iPhone and delivers it to your [OpenClaw](https://github.com/openclaw) instance via webhooks.

## What It Does

Zaap runs in the background on your iPhone and periodically POSTs structured JSON to your OpenClaw gateway:

| Data Type | Endpoint | Source |
|-----------|----------|--------|
| **Location** | `/hooks/location` | Core Location (continuous background updates) |
| **Sleep** | `/hooks/sleep` | HealthKit sleep analysis |
| **Heart Rate** | `/hooks/heartrate` | HealthKit heart rate samples |
| **Activity** | `/hooks/activity` | HealthKit steps, distance, calories |
| **Workouts** | `/hooks/workout` | HealthKit workout sessions |

There's also a `/hooks/ping` endpoint used by the in-app "Test Connection" button.

## Build & Install

### Prerequisites

- Xcode 16+
- An Apple Developer account (for HealthKit + background location entitlements)
- An iPhone running iOS 17+

### Steps

1. Clone the repo and open the Xcode project:
   ```bash
   git clone <this-repo>
   cd zaap/Zaap
   open Zaap.xcodeproj
   ```

2. Select your development team in **Signing & Capabilities**.

3. Build and run on your device (HealthKit is not available in the simulator).

4. To distribute via TestFlight:
   - Set your bundle identifier and version
   - Archive: **Product → Archive**
   - Upload to App Store Connect
   - Add testers in the TestFlight tab

## App Settings

In the app's **Settings** tab, configure:

- **Hostname** — Your OpenClaw gateway hostname (e.g. `my-gateway.example.com`). The app builds the webhook URL as `https://<hostname>/hooks/<service>`.
- **Bearer Token** — The auth token for your OpenClaw gateway. Sent as `Authorization: Bearer <token>` on every request.

Toggle each data type on/off independently: Location, Sleep, Heart Rate, Activity, Workouts.

## OpenClaw Webhook Setup

To receive Zaap data in your OpenClaw instance, you need to register webhook hooks for each endpoint. Add these to your `openclaw.json` (or equivalent config):

```json
{
  "hooks": [
    {
      "path": "/hooks/location",
      "messageTemplate": "📍 Location update: {{latitude}}, {{longitude}} (accuracy: {{horizontalAccuracy}}m, speed: {{speed}}m/s)"
    },
    {
      "path": "/hooks/sleep",
      "messageTemplate": "😴 Sleep report for {{date}}: {{totalAsleepMinutes}} min asleep (deep: {{deepSleepMinutes}}, REM: {{remSleepMinutes}}, core: {{coreSleepMinutes}})"
    },
    {
      "path": "/hooks/heartrate",
      "messageTemplate": "❤️ Heart rate for {{date}}: avg {{avgBPM}} bpm, resting {{restingBPM}} bpm (range: {{minBPM}}-{{maxBPM}}, {{sampleCount}} samples)"
    },
    {
      "path": "/hooks/activity",
      "messageTemplate": "🏃 Activity for {{date}}: {{steps}} steps, {{distanceMeters}}m, {{activeEnergyKcal}} kcal"
    },
    {
      "path": "/hooks/workout",
      "messageTemplate": "💪 Workout: {{workoutType}} — {{durationMinutes}} min, {{totalCalories}} kcal, {{distanceMeters}}m"
    },
    {
      "path": "/hooks/ping",
      "messageTemplate": "🏓 Ping received at {{timestamp}}"
    }
  ]
}
```

### Payload Schemas

**Location** (`/hooks/location`)
```json
{
  "latitude": 33.4484,
  "longitude": -112.0740,
  "altitude": 331.0,
  "horizontalAccuracy": 5.0,
  "verticalAccuracy": 3.0,
  "speed": 1.2,
  "course": 180.0,
  "timestamp": "2026-02-19T16:30:00Z"
}
```

**Sleep** (`/hooks/sleep`)
```json
{
  "date": "2026-02-18",
  "bedtime": "2026-02-18T22:30:00Z",
  "wakeTime": "2026-02-19T06:15:00Z",
  "totalInBedMinutes": 465,
  "totalAsleepMinutes": 420,
  "deepSleepMinutes": 90,
  "remSleepMinutes": 110,
  "coreSleepMinutes": 220,
  "awakeMinutes": 45,
  "sessions": [
    {
      "startDate": "2026-02-18T22:30:00Z",
      "endDate": "2026-02-19T06:15:00Z",
      "stage": "asleepCore",
      "durationMinutes": 220
    }
  ]
}
```

**Heart Rate** (`/hooks/heartrate`)
```json
{
  "date": "2026-02-19",
  "minBPM": 52.0,
  "maxBPM": 165.0,
  "avgBPM": 72.0,
  "restingBPM": 58.0,
  "sampleCount": 1440,
  "samples": [
    { "bpm": 72.0, "timestamp": "2026-02-19T08:00:00Z" }
  ]
}
```

**Activity** (`/hooks/activity`)
```json
{
  "date": "2026-02-19",
  "steps": 8432,
  "distanceMeters": 6540.0,
  "activeEnergyKcal": 385.0,
  "timestamp": "2026-02-19T16:30:00Z"
}
```

**Workout** (`/hooks/workout`) — array of sessions:
```json
[
  {
    "workoutType": "running",
    "startDate": "2026-02-19T06:30:00Z",
    "endDate": "2026-02-19T07:15:00Z",
    "durationMinutes": 45,
    "totalCalories": 520.0,
    "distanceMeters": 7200.0
  }
]
```

## Privacy & Permissions

Zaap requests the following permissions:

- **Location (Always)** — Required for background location tracking. Uses "significant location change" monitoring to minimize battery impact.
- **HealthKit** — Read access for sleep analysis, heart rate, step count, walking/running distance, active energy, and workouts.
- **Background Modes** — Location updates and background fetch for reliable delivery.

All data is sent only to the hostname you configure. No third-party analytics or tracking. No data leaves your device except to your own server.

## License

Private — not for redistribution.
