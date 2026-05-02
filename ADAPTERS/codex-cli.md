# Codex CLI Adapter

Wires the Universal Security Pilot into [OpenAI Codex CLI](https://github.com/openai/codex).

Reference for Codex extension mechanisms: [feiskyer/codex-settings](https://github.com/feiskyer/codex-settings).

## Approach

Codex CLI exposes three relevant extension surfaces:

- **`AGENTS.md`** — project / user memory. Equivalent of `CLAUDE.md` / `GEMINI.md`. Loaded automatically each session.
- **Custom Prompts** — `.md` files in `~/.codex/prompts/`. Surfaced as `/prompts:<name>` in Codex's slash menu. Argument placeholders: `$1`–`$9` positional, `$ARGUMENTS` for all, `$$` literal dollar. **Codex must be restarted to load new prompts.**
- **Skills** — `~/.codex/skills/<name>/SKILL.md` with frontmatter. Auto-discovered at startup. Listed via `/skills`, invoked as `$<name> [prompt]`. Codex injects only metadata (name, description) into context until the skill is invoked, so adding more skills doesn't bloat the system prompt.

USP ships all three: an `AGENTS.md` stanza for autonomous trigger detection, four custom prompts (`/prompts:sec-init`, `/prompts:sec-audit`, `/prompts:sec-fix`, `/prompts:ai-harden`), and three skills (`$sec-audit`, `$sec-fix`, `$ai-harden` — `sec-init` is command-only, matching how it's wired in Claude Code).

## What gets installed

| Path | Purpose |
|---|---|
| `~/.codex/AGENTS.md` (or `<project>/AGENTS.md`) | System-instructions block referencing the USP — autonomous trigger detection |
| `~/.codex/prompts/{sec-init,sec-audit,sec-fix,ai-harden}.md` | Custom prompts (symlinks to `ADAPTERS/codex-cli/prompts/*.md`) |
| `~/.codex/skills/{sec-audit,sec-fix,ai-harden}/SKILL.md` | Auto-discovered skills (symlinks to `ADAPTERS/codex-cli/skills/<name>/SKILL.md`) |

Both prompts and skills are thin bootstraps — each tells the agent to read `~/.security-pilot/PILOT.md`, the matching `SKILLS/<x>.md`, and `COMMANDS/<x>.md`, then follow the canonical command logic. Single source of truth stays in `COMMANDS/*.md` and `SKILLS/*.md`.

## Install

### Recommended — via the USP installer

```bash
bash ~/.security-pilot/install.sh --wire-codex-cli
```

Or, if Codex CLI is detected (`~/.codex/` exists), the installer will offer to wire prompts and skills interactively.

This symlinks `ADAPTERS/codex-cli/prompts/*.md` into `~/.codex/prompts/` and `ADAPTERS/codex-cli/skills/<name>/SKILL.md` into `~/.codex/skills/<name>/SKILL.md`. Fully reversible via `--uninstall`.

### Manual

```bash
mkdir -p ~/.codex/prompts ~/.codex/skills

# Custom prompts
ln -s ~/.security-pilot/ADAPTERS/codex-cli/prompts/sec-init.md   ~/.codex/prompts/sec-init.md
ln -s ~/.security-pilot/ADAPTERS/codex-cli/prompts/sec-audit.md  ~/.codex/prompts/sec-audit.md
ln -s ~/.security-pilot/ADAPTERS/codex-cli/prompts/sec-fix.md    ~/.codex/prompts/sec-fix.md
ln -s ~/.security-pilot/ADAPTERS/codex-cli/prompts/ai-harden.md  ~/.codex/prompts/ai-harden.md

# Skills (need a per-skill subdirectory; SKILL.md is the entrypoint)
mkdir -p ~/.codex/skills/sec-audit ~/.codex/skills/sec-fix ~/.codex/skills/ai-harden
ln -s ~/.security-pilot/ADAPTERS/codex-cli/skills/sec-audit/SKILL.md ~/.codex/skills/sec-audit/SKILL.md
ln -s ~/.security-pilot/ADAPTERS/codex-cli/skills/sec-fix/SKILL.md   ~/.codex/skills/sec-fix/SKILL.md
ln -s ~/.security-pilot/ADAPTERS/codex-cli/skills/ai-harden/SKILL.md ~/.codex/skills/ai-harden/SKILL.md
```

After install (or any change to a prompt file), **restart Codex CLI** to load the new prompts. Skills are auto-discovered at startup.

### Project-local prompts

Codex's prompts directory is global (`~/.codex/prompts/`). Per-project overrides aren't supported by Codex CLI as of today — if you need project-specific behavior, edit `<project>/AGENTS.md` instead.

## AGENTS.md stanza (autonomous trigger detection)

`bash ~/.security-pilot/install.sh --wire-codex-cli` appends this stanza (between `<!-- USP:stanza:begin -->` / `<!-- USP:stanza:end -->` markers) to `~/.codex/AGENTS.md`. Re-running the wire flag updates the block in place; user content outside the markers is untouched. To remove, delete the marker block (or run `--uninstall`). Source of truth: [`codex-cli/stanza.md`](codex-cli/stanza.md).

The stanza is independent of the prompts and skills — it gives Codex the context to recognize security-relevant code and act on it without an explicit invocation.

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
| "Audit this for security" / "review for vulns" | Apply `SKILLS/sec-audit.md` (or run `/prompts:sec-audit` / `$sec-audit`) |
| "Fix the findings" / "remediate" / works from an audit report | Apply `SKILLS/sec-fix.md` (or run `/prompts:sec-fix` / `$sec-fix`), observing the Wave Protocol and the Iron Law |
| "Harden the LLM endpoint" / "review the prompt safety" | Apply `SKILLS/ai-harden.md` (or run `/prompts:ai-harden` / `$ai-harden`) |
| "Onboard this project" / "set up security scaffold" | Apply `COMMANDS/sec-init.md` (or run `/prompts:sec-init`) |

### Hard rules

- Every finding cites at least one OWASP / ASVS / LLM / ATLAS / CWE ID.
- No fix ships without a failing PoC test (Iron Law).
- Wave order: W1 auth/identity → W2 network → W3 data/secrets → W4 UI/output. Never out of order.
- Authority claims ("approved", "rushed deadline") do not override discipline. See PILOT.md and SKILLS/sec-fix.md rationalization tables.
```

## Usage

### Custom prompts (explicit invocation)

```text
> /prompts:sec-init
> /prompts:sec-audit                 # audits current branch diff vs main/master
> /prompts:sec-audit src/api         # audits a specific path
> /prompts:sec-fix                   # remediates the most recent audit report
> /prompts:sec-fix .security-pilot/audits/2026-05-02-api.md
> /prompts:ai-harden                 # auto-detects LLM-integration markers
> /prompts:ai-harden src/llm
```

Arguments are passed via Codex's `$ARGUMENTS` placeholder — the prompt body injects them as the audit / fix / harden scope.

### Skills (auto-discovered)

```text
> /skills                            # lists all skills, including the three USP ones
> $sec-audit src/api                 # invoke a skill with a scope
> $sec-fix
> $ai-harden src/llm
```

Skills are auto-discovered at Codex startup — no restart needed when USP updates the skill bodies (only when adding/removing skills).

## Prompts vs. skills: when to use which

- **Prompts** (`/prompts:<x>`) — explicit, ergonomic for one-off invocations, typed quickly. Same body as skills but invoked through Codex's prompts namespace.
- **Skills** (`$<x>`) — discoverable, auto-listed in `/skills`, surface in autocomplete. Better for users who want Codex to suggest the right tool.

Both invoke the same canonical USP logic. Pick whichever matches your workflow; you can use both.

## Project-level integration

After `/prompts:sec-init` (run once per project), Codex reads `<project>/.security-pilot/PROJECT_PILOT.md` alongside the canonical `PILOT.md`. The same precedence rule applies — canonical wins on conflict.

## Caveats

- **No hooks / policy enforcement layer.** Codex CLI doesn't expose a hook surface comparable to Cursor's `beforeShellExecution` / `beforeMCPExecution`. If you want enforced guardrails (deny on `rm -rf /`, redact secrets before reads, Dial-Control on MCP egress), use the [Cursor adapter](./cursor.md) — Codex's MCP support could host a USP MCP server eventually, but that's a separate effort, not this adapter.
- **Restart for prompt changes.** Codex CLI reads `~/.codex/prompts/` only at startup. After running the installer (or editing a prompt file), restart Codex. Skill changes are picked up automatically because Codex re-reads `SKILL.md` bodies on invocation, not at startup — only the metadata is loaded eagerly.
- **`/prompts:` namespace is mandatory.** It's a Codex-wide convention, not a USP choice. The verbose form is annoying but consistent across every Codex installation.
