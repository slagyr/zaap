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

## Session Completion

Work is NOT complete until `git push` succeeds.

```bash
git add -A && git commit -m "<summary> (<bead-id>)"
git pull --rebase
bd sync
git push
```
