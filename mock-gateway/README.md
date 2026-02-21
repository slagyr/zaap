# mock-gateway

Lightweight local webhook server for testing Zaap in the simulator without hitting the real OpenClaw gateway.

## Start

```bash
node mock-gateway/server.js
# or
cd mock-gateway && npm start
```

The server starts on port `8788` by default.

## Configure the Simulator

In Zaap Settings (simulator), set:
- **Hostname**: `localhost:8788`
- **Token**: anything (not validated)

Or inject via simctl:
```bash
SIM=<your-simulator-uuid>
xcrun simctl spawn $SIM defaults write co.airworthy.zaap settings.webhookURL "localhost:8788"
xcrun simctl spawn $SIM defaults write co.airworthy.zaap settings.authToken "mock"
```

## Live Config

Edit `mock-gateway/config.json` while the server is running — changes apply on the next request, no restart needed.

```json
{
  "port": 8788,
  "fail": {
    "enabled": false,
    "paths": [],
    "statusCode": 500,
    "body": "simulated failure"
  },
  "delay": 0
}
```

### Config Options

| Key | Description |
|-----|-------------|
| `port` | Port to listen on (requires restart to change) |
| `fail.enabled` | Master switch for failure injection |
| `fail.paths` | Paths to fail — e.g. `["location", "sleep"]`. Empty = fail all. |
| `fail.statusCode` | HTTP status returned on failure (default: `500`) |
| `fail.body` | Response body returned on failure |
| `delay` | Milliseconds to delay every response (simulates slow gateway) |

### Examples

**Fail all requests:**
```json
{ "fail": { "enabled": true, "paths": [], "statusCode": 500 } }
```

**Fail only location, succeed everything else:**
```json
{ "fail": { "enabled": true, "paths": ["location"], "statusCode": 503 } }
```

**Simulate a slow gateway (2 second delay):**
```json
{ "delay": 2000 }
```

**Return 401 (bad token) for all requests:**
```json
{ "fail": { "enabled": true, "paths": [], "statusCode": 401, "body": "unauthorized" } }
```
