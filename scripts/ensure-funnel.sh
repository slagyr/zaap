#!/bin/bash
# ensure-funnel.sh — Re-enable Tailscale Funnel after gateway restart
# Fixes: tailscale serve (run by gateway) overwrites funnel config,
# leaving Zaap on iPhone unable to reach the server externally.
#
# Install as launchd agent: ai.openclaw.tailscale-funnel.plist
# Bead: zaap-ho4

set -euo pipefail

TAILSCALE="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
GATEWAY_PORT=18789
VOICE_PORT=3334
LOG="/Users/zane/.openclaw/logs/ensure-funnel.log"
MAX_WAIT=60

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

# Wait for gateway to be listening
waited=0
while ! curl -sf http://127.0.0.1:${GATEWAY_PORT}/health >/dev/null 2>&1; do
  if [ $waited -ge $MAX_WAIT ]; then
    log "ERROR: Gateway not ready after ${MAX_WAIT}s, proceeding anyway"
    break
  fi
  sleep 2
  waited=$((waited + 2))
done

log "Gateway ready (waited ${waited}s), enabling funnel..."

# Enable funnel on all required paths
"$TAILSCALE" funnel --bg --set-path / "http://127.0.0.1:${GATEWAY_PORT}" 2>>"$LOG" || true
"$TAILSCALE" funnel --bg --set-path /hooks "http://127.0.0.1:${GATEWAY_PORT}/hooks" 2>>"$LOG" || true
"$TAILSCALE" funnel --bg --set-path /hooks/sms "http://127.0.0.1:${GATEWAY_PORT}/hooks/sms" 2>>"$LOG" || true
"$TAILSCALE" funnel --bg --set-path /googlechat "http://127.0.0.1:${GATEWAY_PORT}" 2>>"$LOG" || true
"$TAILSCALE" funnel --bg --set-path /voice "http://127.0.0.1:${VOICE_PORT}" 2>>"$LOG" || true

log "Funnel configuration complete"
"$TAILSCALE" funnel status >> "$LOG" 2>&1 || true
