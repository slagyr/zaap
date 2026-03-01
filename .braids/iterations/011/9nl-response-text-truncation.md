# zaap-9nl: Response text truncated — only first few words appear on screen

## Root Cause

In `VoiceChatCoordinator.handleChatEvent`, the "final" case called `viewModel.handleResponseComplete()` without first setting the authoritative final text via `viewModel.setResponseText(t)`.

The flow was:
1. Delta events stream in, each calling `viewModel.setResponseText(t)` with cumulative text
2. Final event arrives, calls `handleResponseComplete()` which logs whatever is in `responseText` then clears it
3. **Problem**: Since `gatewayDidReceiveEvent` is `nonisolated` and dispatches via `Task { @MainActor in }`, Task execution order is not guaranteed. The final event's Task could execute before late delta Tasks, causing `responseText` to contain only partial text.
4. If no delta events arrive before the final, `responseText` would be empty and nothing gets logged.

## Fix

Added `viewModel.setResponseText(t)` in the "final" case before `handleResponseComplete()`, ensuring the full authoritative response text is always set regardless of delta Task ordering.

## Tests Added

- `testChatFinalSetsResponseTextBeforeCompletingSoFullTextIsLogged`
- `testChatFinalWithNoDeltas_logsFullText`

## Commit

Fix included in `fd6854b` (zaap-26w).
