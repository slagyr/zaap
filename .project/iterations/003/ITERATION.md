# Iteration 003

- **Status:** active

## Stories
- zaap-9b7: Delivery log persistence — store webhook deliveries locally
- zaap-8by: Dashboard screen with 7-day bar chart (depends on zaap-9b7)
- zaap-0es: Wire delivery services to log (depends on zaap-9b7)
- zaap-lxv: Tab bar navigation — Dashboard + Settings (depends on zaap-8by)
- zaap-3t6: App icon — creative and fun Zaap branding

## Guardrails
- Follow TDD — read ~/.openclaw/skills/tdd/SKILL.md before writing code
- All new Swift files must be added to project.pbxproj
- Use Swift Charts (built-in, no third-party deps)
- SwiftData for persistence (iOS 17+)
- No build artifacts in git commits
- Verify build compiles and tests pass before pushing

## Notes
- zaap-9b7 is the foundation — chart and wiring both depend on it
- zaap-3t6 (app icon) has no code dependencies, can run in parallel
- Dependency chain: 9b7 → [8by, 0es] → lxv
