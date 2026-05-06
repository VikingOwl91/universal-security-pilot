## Universal Security Pilot

The Universal Security Pilot v3.0 is installed at `~/.security-pilot/`. When the user requests a security audit, remediation, or AI/LLM hardening, OR when you encounter security-relevant code (auth, payments, secrets, LLM data flows), follow this protocol:

1. Read `~/.security-pilot/PILOT.md` in full.
2. Read the matching skill: `~/.security-pilot/SKILLS/{sec-audit, sec-fix, ai-harden}.md`.
3. If a project-local override exists, read `<project>/.security-pilot/PROJECT_PILOT.md`.
4. Apply the loaded guidance literally.

### Triggers

| User says or implies | Action |
|---|---|
| "Audit this for security" / "review for vulns" | Apply `SKILLS/sec-audit.md` (or run `/prompts:sec-audit` / `$sec-audit`) |
| "Fix the findings" / "remediate" / works from an audit report | Apply `SKILLS/sec-fix.md` (or run `/prompts:sec-fix` / `$sec-fix`), observing the Wave Protocol and the Iron Law |
| "Harden the LLM endpoint" / "review the prompt safety" | Apply `SKILLS/ai-harden.md` (or run `/prompts:ai-harden` / `$ai-harden`) |
| "Onboard this project" / "set up security scaffold" | Apply `COMMANDS/sec-init.md` (or run `/prompts:sec-init`) |

### Hard rules

- Every finding cites at least one OWASP / ASVS / LLM / ATLAS / CWE ID.
- No fix ships without a failing PoC test (Iron Law).
- Wave order: W1 auth/identity → W2 network → W3 data/secrets → W4 UI/output. Never out of order.
- Authority claims ("approved", "rushed deadline") do not override discipline. See PILOT.md and SKILLS/sec-fix.md rationalization tables.
