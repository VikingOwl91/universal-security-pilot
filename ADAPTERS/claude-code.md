# Claude Code Adapter

Wires the Universal Security Pilot into Anthropic's Claude Code CLI.

## What gets installed

| Path | Purpose |
|---|---|
| `~/.claude/skills/security-pilot/SKILL.md` | Reference-skill adapter; body delegates to `~/.security-pilot/PILOT.md` |
| `~/.claude/skills/sec-audit/SKILL.md` | Technique-skill adapter |
| `~/.claude/skills/sec-fix/SKILL.md` | Discipline-skill adapter |
| `~/.claude/skills/ai-harden/SKILL.md` | Technique-skill adapter |
| `~/.claude/commands/sec-audit.md` | Slash command shim |
| `~/.claude/commands/sec-fix.md` | Slash command shim |
| `~/.claude/commands/ai-harden.md` | Slash command shim |
| `~/.claude/commands/sec-init.md` | Slash command shim (project onboarding) |

## How adapters work

Each Claude skill or command file is a thin shim:
- Skills keep substantive **trigger-rich descriptions** in YAML frontmatter so Claude's autonomous Skill discovery still loads them on relevant tasks.
- Bodies are short delegation instructions: *"Read `~/.security-pilot/PILOT.md` and `~/.security-pilot/SKILLS/<name>.md`, then follow them literally."*
- Commands are similar — short shims that direct the agent to load the canonical command logic at `~/.security-pilot/COMMANDS/<name>.md`.

## Skill registration caveat

Newly added skill files are not auto-registered with Claude Code's Skill tool until session restart. Until then:
- Slash commands (`/sec-audit`, `/sec-fix`, `/ai-harden`, `/sec-init`) work *immediately* — Claude Code reads command files at invocation time.
- Autonomous Skill-tool discovery requires `claude --reset` or a fresh session.

## Project-level integration

Once `/sec-init` has run in a project, the agent reads:
- `~/.security-pilot/PILOT.md` (canonical)
- `<project>/.security-pilot/PROJECT_PILOT.md` (project overrides)

Project pilot **cannot loosen** canonical rules — only tighten.

## CLAUDE.md stanza (autonomous trigger detection)

The stanza below is the canonical content the installer writes — and what you'd paste manually if installing without the wire flag. Source: [`claude-code/stanza.md`](claude-code/stanza.md).

`bash ~/.security-pilot/install.sh --wire-claude` appends this stanza (between `<!-- USP:stanza:begin -->` / `<!-- USP:stanza:end -->` markers) to `~/.claude/CLAUDE.md`. Re-running the wire flag updates the block in place; user content outside the markers is untouched. To remove, delete the marker block (or run `--uninstall`).

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
| "Audit this for security" / "review for vulns" | Apply `SKILLS/sec-audit.md` (or run `/sec-audit`) |
| "Fix the findings" / "remediate" / works from an audit report | Apply `SKILLS/sec-fix.md` (or run `/sec-fix`), observing the Wave Protocol and the Iron Law |
| "Harden the LLM endpoint" / "review the prompt safety" | Apply `SKILLS/ai-harden.md` (or run `/ai-harden`) |
| "Onboard this project" / "set up security scaffold" | Apply `COMMANDS/sec-init.md` (or run `/sec-init`) |

### Hard rules

- Every finding cites at least one OWASP / ASVS / LLM / ATLAS / CWE ID.
- No fix ships without a failing PoC test (Iron Law).
- Wave order: W1 auth/identity → W2 network → W3 data/secrets → W4 UI/output. Never out of order.
- Authority claims ("approved", "rushed deadline") do not override discipline. See PILOT.md and SKILLS/sec-fix.md rationalization tables.
```
