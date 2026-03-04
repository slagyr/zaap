# zaap-kck: Show pending retry count at top of request log

## Summary
Feature was already fully implemented as part of zaap-qpt (retry queue). No additional code changes needed.

## Acceptance Criteria — All Met
- ✅ RequestLogView shows pending count when WebhookRetryQueue.count > 0
- ✅ Count updates live as queue drains (via onCountChange callback)
- ✅ Nothing shown when queue is empty
- ✅ Depends on zaap-qpt (closed)
