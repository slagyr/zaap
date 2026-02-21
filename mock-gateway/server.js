#!/usr/bin/env node
/**
 * mock-gateway — local webhook server for Zaap simulator testing.
 *
 * Accepts POST /hooks/* and returns configurable responses.
 * Edit config.json while running to change behavior — changes apply immediately.
 *
 * Config options:
 *   port          — port to listen on (default: 8788)
 *   fail.enabled  — master switch for failure injection
 *   fail.paths    — array of path names to fail (e.g. ["location", "sleep"])
 *                   empty = fail ALL paths when enabled
 *   fail.statusCode — HTTP status to return on failure (default: 500)
 *   fail.body     — response body on failure
 *   delay         — ms to delay every response (simulates slow gateway)
 *
 * Usage:
 *   node mock-gateway/server.js
 *   node mock-gateway/server.js --config mock-gateway/config.json
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const configPath = process.argv.includes('--config')
  ? process.argv[process.argv.indexOf('--config') + 1]
  : path.join(__dirname, 'config.json');

// ─── Config ───────────────────────────────────────────────────────────────────

function loadConfig() {
  try {
    const raw = fs.readFileSync(configPath, 'utf8');
    return JSON.parse(raw);
  } catch (err) {
    console.error(`[mock-gateway] Failed to read config: ${err.message}`);
    return null;
  }
}

// ─── Logging ──────────────────────────────────────────────────────────────────

function timestamp() {
  return new Date().toISOString().replace('T', ' ').slice(0, 19);
}

function log(method, urlPath, status, bodyPreview, delayMs) {
  const statusLabel = status >= 500 ? `\x1b[31m${status}\x1b[0m`
                    : status >= 400 ? `\x1b[33m${status}\x1b[0m`
                    : `\x1b[32m${status}\x1b[0m`;
  const delayStr = delayMs > 0 ? ` (+${delayMs}ms delay)` : '';
  const preview = bodyPreview.length > 120 ? bodyPreview.slice(0, 120) + '…' : bodyPreview;
  console.log(`[${timestamp()}] ${method} ${urlPath} → ${statusLabel}${delayStr}`);
  if (preview) console.log(`  body: ${preview}`);
}

// ─── Request handler ──────────────────────────────────────────────────────────

function shouldFail(config, urlPath) {
  const fail = config.fail;
  if (!fail || !fail.enabled) return false;

  const pathName = urlPath.replace(/^\/hooks\//, '').split('?')[0];

  if (!fail.paths || fail.paths.length === 0) return true; // fail everything

  return fail.paths.some(p => p === pathName || urlPath.endsWith(p));
}

function handleRequest(req, res) {
  const config = loadConfig();
  if (!config) {
    res.writeHead(503);
    res.end('mock-gateway: config read error');
    return;
  }

  const urlPath = req.url || '/';
  const delayMs = typeof config.delay === 'number' ? config.delay : 0;

  // Collect body
  const chunks = [];
  req.on('data', chunk => chunks.push(chunk));
  req.on('end', () => {
    const body = Buffer.concat(chunks).toString('utf8');
    const failing = shouldFail(config, urlPath);
    const status = failing ? (config.fail.statusCode || 500) : 200;
    const responseBody = failing
      ? (config.fail.body || 'simulated failure')
      : JSON.stringify({ ok: true, mock: true, path: urlPath });

    const send = () => {
      res.writeHead(status, {
        'Content-Type': 'application/json',
        'X-Mock-Gateway': 'true',
      });
      res.end(responseBody);
      log(req.method, urlPath, status, body, delayMs);
    };

    if (delayMs > 0) {
      setTimeout(send, delayMs);
    } else {
      send();
    }
  });
}

// ─── Server ───────────────────────────────────────────────────────────────────

const initialConfig = loadConfig();
const port = initialConfig?.port || 8788;

const server = http.createServer(handleRequest);

server.listen(port, '0.0.0.0', () => {
  console.log(`\x1b[1m[mock-gateway]\x1b[0m listening on http://localhost:${port}`);
  console.log(`  config: ${configPath}`);
  console.log(`  edit config.json to toggle failure injection — no restart needed\n`);
  console.log(`  Simulator hostname: localhost:${port}`);
  console.log(`  Token:              any value (not validated)\n`);
});

server.on('error', err => {
  console.error(`[mock-gateway] Server error: ${err.message}`);
  process.exit(1);
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n[mock-gateway] Shutting down.');
  server.close(() => process.exit(0));
});
