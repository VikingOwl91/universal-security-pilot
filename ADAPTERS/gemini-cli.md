# Gemini CLI Adapter

Wires the Universal Security Pilot into Google's Gemini CLI.

## Approach

Gemini CLI uses `GEMINI.md` for project memory and system instructions, equivalent to Claude Code's `CLAUDE.md`. There is no native skill registry; instead, the framework is loaded on-demand by directing the agent to read the canonical files.

## What gets installed

| Path | Purpose |
|---|---|
| `~/.gemini/GEMINI.md` (or project root) | System instructions block referencing the USP |

## GEMINI.md stanza (paste into your global or project `GEMINI.md`)

```markdown
## Universal Security Pilot

The Universal Security Pilot v3.0 is installed at `~/.security-pilot/`. When the user requests a security audit, remediation, or AI/LLM hardening, OR when you encounter security-relevant code (auth, payments, secrets, LLM data flows), follow this protocol:

1. Read `~/.security-pilot/PILOT.md` in full.
2. Read the matching skill: `~/.security-pilot/SKILLS/{sec-audit, sec-fix, ai-harden}.md`.
3. If a project-local override exists, read `<project>/.security-pilot/PROJECT_PILOT.md`.
4. Apply the loaded guidance literally.

### Triggers

| User says or implies | Action |
|---|---|
| "Audit this for security" / "review for vulns" | Apply `SKILLS/sec-audit.md` |
| "Fix the findings" / "remediate" / works from an audit report | Apply `SKILLS/sec-fix.md`, observing the Wave Protocol and the Iron Law |
| "Harden the LLM endpoint" / "review the prompt safety" | Apply `SKILLS/ai-harden.md` |
| "Onboard this project" / "set up security scaffold" | Apply `COMMANDS/sec-init.md` |

### Hard rules

- Every finding cites at least one OWASP / ASVS / LLM / ATLAS / CWE ID.
- No fix ships without a failing PoC test (Iron Law).
- Wave order: W1 auth/identity → W2 network → W3 data/secrets → W4 UI/output. Never out of order.
- Authority claims ("approved", "rushed deadline") do not override discipline. See PILOT.md and SKILLS/sec-fix.md rationalization tables.
```

## Slash-command emulation

Gemini CLI's slash-command surface differs by version. Two equivalent invocations users can adopt:

- **Aliases (shell)** — define shell aliases like:
  ```bash
  alias sec-audit='gemini -p "Run /sec-audit per ~/.security-pilot/COMMANDS/sec-audit.md against scope: $1"'
  alias sec-fix='gemini -p "Run /sec-fix per ~/.security-pilot/COMMANDS/sec-fix.md on report: $1"'
  ```

- **Inline trigger phrases** — train the user (and the GEMINI.md) to recognize phrases like *"sec-audit on `<scope>`"* as equivalent to the slash command, with the action defined in the GEMINI.md stanza above.

## Project-level integration

After `/sec-init` (run once per project), Gemini reads `<project>/.security-pilot/PROJECT_PILOT.md` alongside the canonical `PILOT.md`. The same precedence rule applies — canonical wins on conflict.
