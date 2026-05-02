# Gemini CLI Adapter

Wires the Universal Security Pilot into Google's [Gemini CLI](https://github.com/google-gemini/gemini-cli).

## Approach

Gemini CLI exposes two surfaces relevant to USP:

- **`GEMINI.md`** — project / user memory, equivalent to Claude Code's `CLAUDE.md`. Loaded automatically each session.
- **Custom commands** — TOML files under `~/.gemini/commands/` (user-global) or `<project>/.gemini/commands/` (project-local). Project commands override user commands of the same name. See [the official spec](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/custom-commands.md).

USP ships both: a `GEMINI.md` stanza for autonomous trigger detection, and four TOML custom commands (`/sec-init`, `/sec-audit`, `/sec-fix`, `/ai-harden`) for explicit invocation.

## What gets installed

| Path | Purpose |
|---|---|
| `~/.gemini/GEMINI.md` (or `<project>/GEMINI.md`) | System-instructions block referencing the USP — autonomous trigger detection |
| `~/.gemini/commands/sec-init.toml` | `/sec-init` slash command |
| `~/.gemini/commands/sec-audit.toml` | `/sec-audit` slash command |
| `~/.gemini/commands/sec-fix.toml` | `/sec-fix` slash command |
| `~/.gemini/commands/ai-harden.toml` | `/ai-harden` slash command |

The TOML files are thin bootstraps: each one tells the agent to read `~/.security-pilot/PILOT.md`, the matching `SKILLS/<x>.md`, and the matching `COMMANDS/<x>.md`, then execute the canonical command logic. The single source of truth stays in `COMMANDS/*.md` — TOML files don't duplicate it.

## Install

### Recommended — via the USP installer

```bash
bash ~/.security-pilot/install.sh --wire-gemini-cli
```

Or, if Gemini CLI is detected (`~/.gemini/` exists), the installer will offer to wire commands interactively.

This symlinks `ADAPTERS/gemini-cli/commands/*.toml` into `~/.gemini/commands/` and is fully reversible via `--uninstall`.

### Manual

```bash
mkdir -p ~/.gemini/commands
ln -s ~/.security-pilot/ADAPTERS/gemini-cli/commands/sec-init.toml   ~/.gemini/commands/sec-init.toml
ln -s ~/.security-pilot/ADAPTERS/gemini-cli/commands/sec-audit.toml  ~/.gemini/commands/sec-audit.toml
ln -s ~/.security-pilot/ADAPTERS/gemini-cli/commands/sec-fix.toml    ~/.gemini/commands/sec-fix.toml
ln -s ~/.security-pilot/ADAPTERS/gemini-cli/commands/ai-harden.toml  ~/.gemini/commands/ai-harden.toml
```

After install (or after editing any TOML), run `/commands reload` inside Gemini CLI to pick the changes up without restarting.

### Project-local overrides

Drop a TOML of the same basename into `<project>/.gemini/commands/`. Gemini CLI will use the project version. Useful for tightening prompts on a per-project basis (for example, making `/sec-audit` always default to a specific subdirectory).

## GEMINI.md stanza (paste into your global or project `GEMINI.md`)

The stanza is independent of the slash commands — it gives Gemini the context to recognize security-relevant code and act on it without an explicit command.

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

## Usage

```text
> /sec-init
> /sec-audit                  # audits current branch diff vs main/master
> /sec-audit src/api          # audits a specific path
> /sec-fix                    # remediates the most recent audit report
> /sec-fix .security-pilot/audits/2026-05-02-api.md
> /ai-harden                  # auto-detects LLM-integration markers
> /ai-harden src/llm
```

Arguments are passed via Gemini CLI's `{{args}}` substitution — the TOML prompts inject them as the audit / fix / harden scope.

## Project-level integration

After `/sec-init` (run once per project), Gemini reads `<project>/.security-pilot/PROJECT_PILOT.md` alongside the canonical `PILOT.md`. The same precedence rule applies — canonical wins on conflict.
