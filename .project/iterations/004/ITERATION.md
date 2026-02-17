# Iteration 004

- **Status:** active

## Stories
- zaap-fkp: Per-service path routing — base URL is /hooks, each service appends its own path
- zaap-r25: Webhook test button — verify config with a ping (depends on zaap-fkp)
- zaap-4jt: Send Now buttons — manual trigger for each data source (depends on zaap-fkp)

## Guardrails
- Follow TDD — read ~/.openclaw/skills/tdd/SKILL.md before writing any code
- All new Swift files must be added to project.pbxproj
- Fix crash on invalid/missing webhook URL — graceful error handling everywhere
- Verify build compiles AND tests pass before pushing
- No build artifacts in commits
- Bump build number after all stories complete for TestFlight upload

## Notes
- App currently crashes on bad webhook config — this iteration fixes that
- zaap-fkp goes first: changes URL architecture that the other two depend on
- After all stories complete, archive and upload build 3 to TestFlight
