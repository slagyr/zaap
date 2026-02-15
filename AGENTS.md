# AGENTS.md

This project is managed by the **projects** skill. Read `.project/PROJECT.md` for goals, guardrails, and settings.

## How to Work on This Project

**If you were spawned by the orchestrator** (your task message includes `Project:` and `Bead:` fields):
→ Follow `~/.openclaw/skills/projects/references/worker.md`
  (or online: https://raw.githubusercontent.com/slagyr/project-skill/refs/heads/main/projects/references/worker.md)

**If you're here on your own** (manual session, human asked you to help, etc.):
1. Read `.project/PROJECT.md` — understand the goal and guardrails
2. Find the active iteration: look in `.project/iterations/*/ITERATION.md` for `Status: active`
3. Run `bd ready` to see available work
4. Pick a bead, then follow the worker workflow: `~/.openclaw/skills/projects/references/worker.md`
   (or online: https://raw.githubusercontent.com/slagyr/project-skill/refs/heads/main/projects/references/worker.md)

## Quick Reference

```bash
bd ready              # List unblocked tasks
bd show <id>          # View task details
bd update <id> --claim  # Claim a task
bd update <id> -s closed  # Close completed task
bd list               # List all tasks
bd dep list <id>      # List dependencies
```

## Session Completion

Work is NOT complete until `git push` succeeds.

```bash
git add -A && git commit -m "<summary> (<bead-id>)"
git pull --rebase
bd sync
git push
```
