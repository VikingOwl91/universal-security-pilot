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

## Optional: extend the global CLAUDE.md

Add a stanza to `~/.claude/CLAUDE.md`:

```markdown
## Security Workflow

The Universal Security Pilot is installed at `~/.security-pilot/`.

- Use `/sec-audit` for security review.
- Use `/sec-fix` for remediation following the Wave Protocol.
- Use `/ai-harden` for LLM/AI data-flow hardening.
- Use `/sec-init` to onboard a new project.

The canonical security rules live in `~/.security-pilot/PILOT.md`. Project overrides live in `<project>/.security-pilot/PROJECT_PILOT.md` after `/sec-init`.
```
