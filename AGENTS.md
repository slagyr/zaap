# AGENTS.md

This project is managed by the **projects** skill. Read `.project/PROJECT.md` for goals, guardrails, and settings.

## Development Practice

**This project follows TDD (Test-Driven Development).** Before writing any implementation code, read and follow the TDD skill:
→ `~/.openclaw/skills/tdd/SKILL.md`

All new features must have tests written first. Red → Green → Refactor.

## How to Work on This Project

**If you were spawned by the orchestrator** (your task message includes `Project:` and `Bead:` fields):
→ Follow `~/.openclaw/skills/braids/references/worker.md`

**If you're here on your own** (manual session, human asked you to help, etc.):
1. Read `.project/PROJECT.md` — understand the goal and guardrails
2. Find the active iteration: look in `.project/iterations/*/ITERATION.md` for `Status: active`
3. Run `bd ready` to see available work
4. Pick a bead, then follow the worker workflow: `~/.openclaw/skills/projects/references/worker.md`
   (or online: https://raw.githubusercontent.com/slagyr/project-skill/refs/heads/main/projects/references/worker.md)

## Quick Reference

```bash
# All bd commands require BEADS_IGNORE_REPO_MISMATCH=1 in this project
BEADS_IGNORE_REPO_MISMATCH=1 bd ready              # List unblocked tasks
BEADS_IGNORE_REPO_MISMATCH=1 bd show <id>          # View task details
BEADS_IGNORE_REPO_MISMATCH=1 bd update <id> --claim  # Claim a task
BEADS_IGNORE_REPO_MISMATCH=1 bd update <id> -s closed  # Close completed task
BEADS_IGNORE_REPO_MISMATCH=1 bd list               # List all tasks
BEADS_IGNORE_REPO_MISMATCH=1 bd dep list <id>      # List dependencies
```

## Git Hooks Setup

After cloning, symlink the pre-push hook to enable coverage enforcement:

```bash
ln -sf ../../scripts/pre-push .git/hooks/pre-push
```

This runs tests with coverage on every `git push` and blocks if any source file falls below 90% coverage.

## Multi-Component Features — Mandatory Integration Bead

When a feature spans multiple components (e.g. VoiceEngine + GatewayConnection + ResponseSpeaker + View), the final bead **must** be an explicit integration/wiring bead that:
1. Instantiates all real production dependencies (not just test doubles)
2. Injects them into the UI (View, not just a coordinator class)
3. Wires all callbacks end-to-end (partial transcripts, errors, state changes)
4. Verifies with `xcodebuild build` that the full app compiles and runs

**Do not mark a feature complete if the components only exist in isolation.** The integration point (the View or App entry point) must explicitly reference all pieces.

Checklist before closing a multi-component bead:
- [ ] Real production implementations exist (not just protocols + test mocks)
- [ ] All dependencies instantiated with concrete types (no missing inits)
- [ ] View/App entry point wired to coordinator/service
- [ ] Callbacks wired (partial results, errors, completion)
- [ ] `xcodebuild build` passes

## Session Completion

Work is NOT complete until `git push` succeeds.

```bash
git add -A && git commit -m "<summary> (<bead-id>)"
git pull --rebase
bd sync
git push
```

## Iteration Completion → TestFlight

When all beads in an iteration are closed and the iteration is marked complete, **build and push to TestFlight**. Do not wait to be asked.

Steps:
1. Bump the build number in `Zaap/Zaap/Info.plist` (`CFBundleVersion`)
2. Archive and export the IPA (use `destination=export` in ExportOptions.plist, **not** `destination=upload`):
   ```bash
   xcodebuild archive -project Zaap/Zaap.xcodeproj -scheme Zaap \
     -archivePath /tmp/Zaap.xcarchive -allowProvisioningUpdates
   xcodebuild -exportArchive -archivePath /tmp/Zaap.xcarchive \
     -exportOptionsPlist /tmp/ExportOptions.plist \
     -exportPath /tmp/ZaapExport -allowProvisioningUpdates
   ```
3. Upload to TestFlight via `altool`:
   ```bash
   xcrun altool --upload-app -f /tmp/ZaapExport/Zaap.ipa \
     --type ios --apiKey 68P29K4Z2B \
     --apiIssuer 69a6de84-bbb3-47e3-e053-5b8c7c11a4d1
   ```
4. Notify Micah in #zaap once the build is processing on TestFlight.
