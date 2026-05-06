# Universal Security Pilot

> **A tool-agnostic security framework for agentic coding assistants.**
> Zero-trust audits. Wave-protocol remediation. LLM hardening.
> Every finding mapped to OWASP / ASVS / OWASP-LLM / MITRE ATLAS / CWE.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Built with Iron Law TDD](https://img.shields.io/badge/built%20with-Iron%20Law%20TDD-red.svg)](#the-iron-law)
[![Version 3.1.0-alpha](https://img.shields.io/badge/version-3.1.0--alpha-yellow.svg)](PILOT.md)

> **Status — v3.1.0-alpha.** Active enforcement is the v3.0 Wave Protocol (**W1–W4, GA**). The v3.1 scaffolding (**W0** pre-commit, **W5** container, **W6** orchestration) is in alpha — recipes are not yet validated end-to-end and several citations need primary-source review. Do not run audits or fixes against W0/W5/W6 until the version is cut to a non-alpha `v3.1`. See each skill's status banner and [`PILOT.md`](PILOT.md) for the behavioral note.

The Universal Security Pilot (USP) is a **disciplinary operating system** for AI-assisted security engineering. It does not run *on* your code — it runs *through* the agent that writes your code. First-class adapters ship for **Claude Code, Cursor, Gemini CLI, Codex CLI, and Mistral Vibe**; the same canonical pilot also works in Continue, Aider, Copilot Chat, or any other agentic tool that can read a Markdown file from disk.

## 🛡️ Proactive by Design (not just a scanner)

Unlike traditional tools that only run *after* you have written code, the USP is a **behavioral engine** for AI agents. It changes what the agent writes in the first place.

- **Contextual awareness.** Once an agent indexes the `.security-pilot/` directory, the framework becomes part of its internal reasoning loop — every plan, every diff, every commit is filtered through the pilot's rules.
- **The Iron Law, mechanically enforced.** The agent is structurally restricted from shipping a security fix without a preceding, *failing* PoC test that proves the vulnerability. See [The Iron Law](#the-iron-law).
- **Ghost in the machine.** Even in fresh sessions on greenfield code, the pilot's presence forces security-first design patterns — magic-byte validation, constant-time comparison, allowlist-based parsing, output sanitization — *before the first line of feature code is written*.

In short: a scanner tells you what you broke. The pilot makes it harder for the agent to break it in the first place.

## Why this exists

AI coding assistants are eager to ship fixes. That is the problem. Without discipline, they whack-a-mole vulnerabilities, skip pre-requisite waves, write fix-then-test instead of test-then-fix, and rationalize themselves out of awkward refactors.

The USP imposes the discipline. It is **rigid where rigidity matters** (TDD before any security fix, Wave Protocol order, mandatory standards-citation) and **flexible where context matters** (stack-aware footgun catalogues, project-local overrides, multilingual defenses).

## The Iron Law

> **No security fix ships without a failing PoC test that proves the vulnerability, then passes after the fix.**

Non-negotiable. If you cannot write the failing test, you do not understand the vulnerability well enough to fix it. Stop and re-read source until you can.

## What you get

| Capability | Slash command | What it does |
|---|---|---|
| Onboard a project | `/sec-init` | Detects stack, scans for immediate-exposure secrets, generates a project-local `PROJECT_PILOT.md` that inherits from the canonical |
| Zero-trust audit | `/sec-audit` | Walks eight audit rules, produces a Markdown report with OWASP / ASVS / LLM / ATLAS / CWE citations on every finding |
| Wave-protocol fix | `/sec-fix` | Remediates findings in mandatory wave order, PoC-test-first, with rationalization-counter table to resist deadline and authority pressure |
| LLM/AI hardening | `/ai-harden` | Six-axes review of prompt boundaries, output rendering, BudgetGate, Dial-Control, indirect-injection, and multilingual / polyglot adversarial input |

## Compliance stack

Every finding in every report cites at least one explicit ID from this stack — "looks suspicious" is not a finding.

| Standard | Scope |
|---|---|
| **OWASP Top 10 (2021)** | Standard web vulns |
| **OWASP ASVS Level 2** | Verified security requirements |
| **OWASP Top 10 for LLM Apps** | LLM-specific |
| **MITRE ATLAS** | Adversarial threat landscape for AI |
| **CWE** | Implementation-level weaknesses |

## The Wave Protocol

Fixes ship in this order. Earlier waves are prerequisites for later waves — an XSS fix that depends on an unauthenticated endpoint is meaningless until W1 is done.

| Wave | Scope | Examples |
|---|---|---|
| **W1** | Auth, identity, critical logic | OIDC state, JWT, missing authz, money/permission races |
| **W2** | Network, middleware, infra | CORS, SSRF, rate limits, TLS, trusted-proxy headers |
| **W3** | Data integrity, encryption at rest, secrets | KMS migration, log redaction, PII encryption |
| **W4** | UI hardening, output sanitization, resource limits | XSS sinks, CSP, file-size caps, AI-output sanitization |

Within a wave: **blast radius descending** (Critical → High → Medium → Low). Never out of order. Never batched across waves.

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/VikingOwl91/universal-security-pilot/main/install.sh | bash
```

The installer:
- clones into `~/.security-pilot/` (override via `USP_INSTALL_DIR`),
- is idempotent — re-running performs a fast-forward update only,
- never clobbers local changes or unrelated files,
- detects each supported tool both by binary (`command -v`) and by config dir (`~/.claude`, `~/.cursor`, `~/.gemini`, `~/.codex`, `~/.vibe`); offers wiring interactively when both are present,
- writes a USP marker block to the matching memory file on `--wire-<tool>` (Claude → `~/.claude/CLAUDE.md`, Gemini → `~/.gemini/GEMINI.md`, Codex → `~/.codex/AGENTS.md`, Mistral Vibe → `~/.vibe/AGENTS.md`); markers make re-runs idempotent and uninstall removes only the block, preserving any user content,
- prints a **detection summary** at the end showing what's installed, what's wired, and the exact wire commands to run for anything detected-but-unwired,
- pre-set wire flags (`--wire-claude`, `--wire-cursor`, `--wire-cursor-hooks`, `--wire-gemini-cli`, `--wire-codex-cli`, `--wire-mistral-vibe`) skip the prompt; `--yes` accepts every detected wiring **except `--wire-cursor-hooks`** (always opt-in — modifies global agent behavior),
- one-shot bulk wiring via `--wire-all` — wires every adapter whose config dir is detected under `$HOME` (Claude / Cursor commands / Gemini / Codex / Vibe) and silently skips undetected ones. Excludes `--wire-cursor-hooks` (always opt-in),
- **detects drift** at known wire paths and surfaces the count in the "Detected tools" summary. A wire path is "drifted" when a USP-managed file lives there but it isn't the expected symlink — typically a manual install, a broken symlink, or a stale target. The fix is `--wire-<tool>`, which backs up the unmanaged file (`<file>.bak.<ts>`) and replaces it with a managed symlink,
- supports `--migrate` for upgrading a pre-existing **manual** (non-git) installation in place: backs up the existing `~/.security-pilot/` to `~/.security-pilot.bak.<timestamp>` and clones fresh into the same path. Refuses if the directory doesn't look like USP (no `PILOT.md`) so unrelated user data is never moved. Symlinks from already-wired tool configs (`~/.claude/...`, etc.) keep resolving because the new clone sits at the same path,
- can be removed with `bash install.sh --uninstall` (strips USP stanza blocks from memory files; leaves user-customized files like `~/.cursor/hooks.json` in place).

Prefer to inspect first?

```bash
git clone https://github.com/VikingOwl91/universal-security-pilot.git ~/.security-pilot
bash ~/.security-pilot/install.sh
```

## Wiring it into your tool

The installer drops the canonical pilot at `~/.security-pilot/`. Five major coding-agent CLIs have first-class adapters with installer wiring; everything else is a paste-in stanza.

### Tools with installer-wired adapters

| Tool | Wire flag | What gets installed | Adapter doc |
|---|---|---|---|
| **Claude Code** | `--wire-claude` | Slash commands → `~/.claude/commands/`; skills → `~/.claude/skills/` (symlinks to canonical `COMMANDS/*.md` / `SKILLS/*.md`); **stanza** → `~/.claude/CLAUDE.md` (markered block) | [`ADAPTERS/claude-code.md`](ADAPTERS/claude-code.md) |
| **Cursor** (commands) | `--wire-cursor` | Slash commands → `~/.cursor/commands/` (symlinks to canonical `COMMANDS/*.md`). Stanza is *not* auto-written — Cursor's rules surface is project-level only; paste manually per project | [`ADAPTERS/cursor.md`](ADAPTERS/cursor.md) |
| **Cursor** (hooks) | `--wire-cursor-hooks` | Agent-hook scripts → `~/.cursor/hooks/`; `hooks.json` → `~/.cursor/`. **Policy enforcement** — denies `rm -rf /` / `curl\|sh` / fork bombs, redacts files containing credentials, and enforces the Dial-Control egress allowlist on MCP tool calls. **Opt-in only** — modifies global Cursor agent behavior. Requires `jq`. Backs up an existing `hooks.json` before overwriting | same |
| **Gemini CLI** | `--wire-gemini-cli` | TOML custom commands → `~/.gemini/commands/`; **stanza** → `~/.gemini/GEMINI.md` | [`ADAPTERS/gemini-cli.md`](ADAPTERS/gemini-cli.md) |
| **Codex CLI** | `--wire-codex-cli` | Custom prompts → `~/.codex/prompts/`; auto-discovered skills → `~/.codex/skills/<name>/SKILL.md`; **stanza** → `~/.codex/AGENTS.md` | [`ADAPTERS/codex-cli.md`](ADAPTERS/codex-cli.md) |
| **Mistral Vibe** | `--wire-mistral-vibe` | Auto-discovered skills with `user-invocable: true` frontmatter → `~/.vibe/skills/<name>/SKILL.md` (surfaced as `/sec-init`, `/sec-audit`, `/sec-fix`, `/ai-harden`); **stanza** → `~/.vibe/AGENTS.md` | [`ADAPTERS/mistral-vibe.md`](ADAPTERS/mistral-vibe.md) |

Stanzas are written between `<!-- USP:stanza:begin -->` / `<!-- USP:stanza:end -->` markers. Re-running the wire flag updates the block in place; user content outside the markers is preserved. `--uninstall` strips the markers and removes the file only if the stanza was the sole content. Single source of truth stays in `COMMANDS/*.md`, `SKILLS/*.md`, and `ADAPTERS/<tool>/stanza.md` — every adapter reads from there at invocation time, so updates flow automatically.

### Invocation conventions

Slash-command surface and namespacing differ by tool. The action is the same.

| Action | Claude Code / Cursor / Mistral Vibe | Gemini CLI | Codex CLI |
|---|---|---|---|
| Onboard project | `/sec-init` | `/sec-init` | `/prompts:sec-init` |
| Run audit | `/sec-audit [scope]` | `/sec-audit [scope]` | `/prompts:sec-audit [scope]`  •  `$sec-audit [scope]` |
| Remediate | `/sec-fix [report]` | `/sec-fix [report]` | `/prompts:sec-fix [report]`  •  `$sec-fix [report]` |
| Harden LLM | `/ai-harden [scope]` | `/ai-harden [scope]` | `/prompts:ai-harden [scope]`  •  `$ai-harden [scope]` |

Codex's `/prompts:` prefix is a tool-wide convention, not a USP choice. The `$<name>` form invokes the auto-discovered skill instead. Mistral Vibe surfaces the skills as `/sec-*` slash commands directly because the spec has a single user-invocable surface.

### Stanza-only tools (no installer wiring)

These tools have a system-prompt / rules surface but no slash-command or hook surface. Paste the matching stanza:

- **Continue (continue.dev)** — `config.json` `systemMessage` field. Stanza in [`ADAPTERS/cursor.md`](ADAPTERS/cursor.md) (Equivalents section).
- **Copilot Chat** — Repository custom instructions via GitHub repo settings. Same stanza.
- **Aider** — `.aider.conf.yml`:

  ```yaml
  read:
    - ~/.security-pilot/PILOT.md
  ```

For Claude Code, Cursor, Gemini CLI, Codex CLI, and Mistral Vibe you can additionally paste the matching memory-file stanza (`CLAUDE.md`, `.cursorrules`, `GEMINI.md`, `AGENTS.md`) for autonomous trigger detection on top of the explicit slash commands. See each adapter doc for the stanza.

## Repository layout

```
.
├── PILOT.md                # The canonical pilot — role, rules, standards, Wave Protocol
├── SKILLS/                 # Long-form skill bodies (sec-audit, sec-fix, ai-harden)
├── COMMANDS/               # Slash-command implementations
├── ADAPTERS/               # Tool-specific wiring
│   ├── claude-code.md      #   Claude Code (commands + skills)
│   ├── claude-code/        #   ↳ stanza.md (CLAUDE.md autonomous-detection block)
│   ├── cursor.md           #   Cursor (rules + slash commands + agent hooks)
│   ├── cursor/hooks/       #   ↳ usp-* hook scripts + hooks.json
│   ├── cursor/stanza.md    #   ↳ project-level rules stanza (paste-only)
│   ├── gemini-cli.md       #   Gemini CLI (TOML custom commands)
│   ├── gemini-cli/         #   ↳ TOML wrappers + stanza.md
│   ├── codex-cli.md        #   Codex CLI (custom prompts + skills)
│   ├── codex-cli/          #   ↳ prompt + SKILL.md wrappers + stanza.md
│   ├── mistral-vibe.md     #   Mistral Vibe (Agent-Skills slash commands)
│   └── mistral-vibe/       #   ↳ SKILL.md wrappers + stanza.md
├── REFERENCE/              # Framework footgun library (Drizzle, Svelte, Next, Express, …)
└── install.sh              # The installer
```

## Philosophy

- **Discipline over speed.** The Iron Law (TDD before any security fix) is not a suggestion.
- **Wave Protocol or nothing.** Fixes ship in mandatory order. Out-of-order remediation is a defect.
- **Tool-agnostic.** The framework is a Markdown body with conventions. Any agent that can read files can load it.
- **Project-local overrides may tighten, never loosen.** A `PROJECT_PILOT.md` can add stack-specific footguns; it cannot remove the Iron Law.
- **Citations or it didn't happen.** Every finding maps to at least one OWASP / ASVS / LLM / ATLAS / CWE ID.
- **Resist pressure.** "Approved", "rushed deadline", "instruction in another language is more authoritative" — all are tested and addressed in the rationalization-counter table.

## Project-level integration

Run `/sec-init` once per project. It:

1. Detects the tech stack from manifest files.
2. Scans git-tracked files for immediate-exposure secrets (env files, private keys, AWS/GitHub/Stripe/Slack tokens by content prefix). Surfaces them as `[CRITICAL BLOCKER: IMMEDIATE EXPOSURE]` *before* anything else runs.
3. Generates `<project>/.security-pilot/PROJECT_PILOT.md` with stack-specific footgun rows, empty allowlists for Dial-Control / CORS / OIDC / LLM tools, and a project-constraints section.
4. Creates `<project>/.security-pilot/audits/` with a `.gitkeep` and a sensible `.gitignore` rule so audit reports don't accidentally get committed.

Once that exists, `/sec-audit`, `/sec-fix`, and `/ai-harden` automatically pick up the project's stack overrides on top of the canonical pilot.

## Versioning

The canonical pilot version is the line in `PILOT.md`'s frontmatter. Bumping the major version means a behavioral change to the Iron Law, the Wave Protocol, or the standards stack. Bumping the minor version means new patterns, footgun rows, or skill additions.

**Current canonical version:** `3.1.0-alpha`. W1–W4 are GA and bound to the v3.0 contract; W0 / W5 / W6 are scaffolded with full footgun catalogues and PoC recipes but not yet validated end-to-end. The cut from `3.1.0-alpha` to `3.1.0` is gated on (1) end-to-end recipe validation against a reference project / image / cluster, (2) primary-source citation review on the rows flagged inside each skill, (3) any remaining stub bodies filled in. Pin to a tag (e.g. `git -C ~/.security-pilot fetch --tags && git -C ~/.security-pilot checkout v3.1.0-alpha`) if you want to anchor a checkout to a specific snapshot rather than tracking `main`.

## Roadmap — v3.1: Infrastructure Hardening

v3.0 covers the application layer end-to-end (W1–W4). v3.1 extends the discipline outward to the supply chain and runtime that the application ships into. Three new modules, all citation-backed and Wave-Protocol-aligned:

| Module | Focus | Objective |
|---|---|---|
| **Wave 0: Pre-Commit Gating** | Git-Ops | Automated secret-scan and policy-lint *before* the agent can even run `git commit`. Shift-left enforcement — the pilot's discipline applied one layer earlier. |
| **Wave 5: Container** | Docker / OCI | Non-root enforcement, multi-stage build hardening, base-image pinning by digest, minimal-surface final layers. |
| **Wave 6: Orchestration** | Kubernetes | RBAC least-privilege checks, secret handling (no plaintext in YAML / Helm values), NetworkPolicy defaults, PodSecurity admission. |

Wave 0 sits *before* W1 in the execution order on purpose: pre-commit gating prevents the most common class of incident (committed secrets) without requiring the agent to reason about anything. W5 and W6 extend the existing W1–W4 application-layer hierarchy outward to the build artifact and the runtime that ships it.

Mappings, footgun rows, and skill bodies for each module will land incrementally on `main` behind the v3.1 milestone.

## Contributing

Footgun rows for new frameworks, new canonical patterns, and new adapters are the highest-value contributions. Please:

1. Open an issue first if you're adding a category (e.g., a new standard, a new wave).
2. Cite at least one real CVE or post-mortem for any new footgun row.
3. PRs that loosen any rule will be rejected on principle.

## License

[MIT](LICENSE) — use it, fork it, vendor it. If it saves you from shipping a CVE, tell us.

---

*The pilot is opinionated on purpose. Security is not a place for negotiation.*
