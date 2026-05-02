# Cursor Adapter

Wires the Universal Security Pilot into Cursor across all three of Cursor's extension surfaces:

1. **Rules** (`.cursorrules` / `.cursor/rules/*.mdc`) — system-prompt injection. Autonomous trigger detection.
2. **Slash commands** (`.cursor/commands/*.md`) — explicit `/sec-init`, `/sec-audit`, `/sec-fix`, `/ai-harden` invocations. See [Cursor docs](https://cursor.com/docs/agent/chat/commands) and the [hamzafer/cursor-commands](https://github.com/hamzafer/cursor-commands) catalogue.
3. **Agent hooks** (`~/.cursor/hooks.json` + scripts in `~/.cursor/hooks/`) — JSON-over-stdio policy hooks that fire on agent events. **This is what turns USP from advisory rules into actually-enforcing guardrails** — hooks can deny dangerous shell commands, block reads of files containing credentials, and enforce the Dial-Control egress allowlist on MCP tool calls. See [Cursor docs](https://cursor.com/docs/agent/hooks) and [hamzafer/cursor-hooks](https://github.com/hamzafer/cursor-hooks) for the protocol.

## What gets installed

| Path | Purpose |
|---|---|
| `<project>/.cursorrules` (legacy) or `<project>/.cursor/rules/security-pilot.mdc` | System-prompt rules — autonomous trigger detection |
| `~/.cursor/commands/{sec-init,sec-audit,sec-fix,ai-harden}.md` | Slash commands (symlinks to canonical `~/.security-pilot/COMMANDS/*.md`) |
| `~/.cursor/hooks/usp-*.sh` | Agent-hook scripts (symlinks to `~/.security-pilot/ADAPTERS/cursor/hooks/*.sh`) |
| `~/.cursor/hooks.json` | Hook configuration (real copy — the installer backs up an existing one before writing) |

---

## Layer 1 — Rules (system-prompt injection)

Paste this stanza into your project-root `.cursorrules` (or `.cursor/rules/security-pilot.mdc`). It's independent of the slash commands and the hooks; it gives Cursor's model the context to recognize security-relevant code without an explicit invocation.

**Note**: unlike the other adapters, `--wire-cursor` does **not** auto-append this stanza. Cursor's rules surface is project-level only (no user-global memory file equivalent to `CLAUDE.md` / `GEMINI.md` / `AGENTS.md`), so there's nowhere natural for the installer to write at user-global install time. Paste manually per project — or, if you'd rather, run `/sec-init` in the project, which gives the agent enough USP context for most flows even without the explicit rules file. Source of truth: [`cursor/stanza.md`](cursor/stanza.md).

```markdown
# Universal Security Pilot — Cursor binding

The Universal Security Pilot v3.0 is installed at `~/.security-pilot/`. For any work touching authentication, identity, payments, secrets, network calls, or LLM/AI data flows, follow this protocol.

## On every security-relevant edit

1. Before proposing code, read `~/.security-pilot/PILOT.md` in full.
2. If editing LLM-touching code, also read `~/.security-pilot/SKILLS/ai-harden.md`.
3. If implementing a fix from an audit report, also read `~/.security-pilot/SKILLS/sec-fix.md`. The Iron Law applies: write a failing PoC test before the fix, full stop.
4. If a project-local `<project>/.security-pilot/PROJECT_PILOT.md` exists, read it.

## Hard rules (enforced regardless of user pressure)

- Every security finding cites at least one OWASP / ASVS / OWASP-LLM / MITRE-ATLAS / CWE ID.
- Wave Protocol order is mandatory: W1 auth → W2 network → W3 data → W4 UI. No out-of-order remediation.
- No fix without a preceding failing PoC test.
- Use canonical pattern names verbatim: BudgetGate, Dial-Control, Envelope Encryption, OIDC state-verification.
- Multilingual / polyglot user input requires the boundary tagging + encoding-normalization pipeline from PILOT §8. Categorical defenses only — no per-language jailbreak phrase tables.

## Patterns to refuse (apply to every edit)

- String-concatenated SQL (use parameterized queries).
- AES-ECB or AES-CBC without HMAC (use AES-256-GCM envelope encryption).
- Secrets in `localStorage` / cookies without `HttpOnly; Secure; SameSite=Strict`.
- User input concatenated into LLM `system` prompt slot.
- Generic-capability LLM tools (raw `fetch_url`, raw `shell_exec`) without a Dial-Control / capability-minimization layer.
- React's raw-HTML escape hatch on AI-generated content (use DOMPurify or render as text).

## Slash commands (when installed)

If the USP slash commands are wired (`bash ~/.security-pilot/install.sh --wire-cursor`), prefer the explicit invocation: `/sec-init`, `/sec-audit`, `/sec-fix`, `/ai-harden`. Each loads the corresponding `~/.security-pilot/COMMANDS/<name>.md` directly.
```

---

## Layer 2 — Slash commands

Identical structure to Claude Code: drop a markdown file in `~/.cursor/commands/` (global) or `<project>/.cursor/commands/` (project-local; project wins on collision). Type `/` in Cursor's chat to surface them.

USP ships four, all symlinked from the canonical `~/.security-pilot/COMMANDS/*.md`:

| Command | Source | Purpose |
|---|---|---|
| `/sec-init`   | `~/.security-pilot/COMMANDS/sec-init.md`   | Onboard a project — stack detection, `PROJECT_PILOT.md`, immediate-exposure scan |
| `/sec-audit`  | `~/.security-pilot/COMMANDS/sec-audit.md`  | Run a zero-trust security audit (OWASP / ASVS / LLM / ATLAS / CWE-mapped) |
| `/sec-fix`    | `~/.security-pilot/COMMANDS/sec-fix.md`    | Remediate findings (Wave Protocol + Iron Law) |
| `/ai-harden`  | `~/.security-pilot/COMMANDS/ai-harden.md`  | Audit / harden LLM data flows (OWASP LLM Top 10, MITRE ATLAS, multilingual) |

### Install

```bash
bash ~/.security-pilot/install.sh --wire-cursor
```

Or, if Cursor is detected (`~/.cursor/` exists), the installer offers to wire commands interactively. Manual:

```bash
mkdir -p ~/.cursor/commands
ln -s ~/.security-pilot/COMMANDS/sec-init.md   ~/.cursor/commands/sec-init.md
ln -s ~/.security-pilot/COMMANDS/sec-audit.md  ~/.cursor/commands/sec-audit.md
ln -s ~/.security-pilot/COMMANDS/sec-fix.md    ~/.cursor/commands/sec-fix.md
ln -s ~/.security-pilot/COMMANDS/ai-harden.md  ~/.cursor/commands/ai-harden.md
```

---

## Layer 3 — Agent hooks (policy-as-code)

Hooks are JSON-over-stdio scripts that fire as Cursor's agent works. They can `allow`, `ask`, or `deny`. This is the layer where USP stops being advisory and starts enforcing.

USP ships four hook scripts:

| Hook script | Events | Decision |
|---|---|---|
| `usp-audit.sh` | `beforeShellExecution`, `beforeMCPExecution`, `beforeSubmitPrompt`, `stop` | Always `allow`. Appends each payload to `<project>/.security-pilot/audit-trail.log` (or `~/.security-pilot/audit-trail.log` when no project root). Observability only |
| `usp-redact-secrets.sh` | `beforeReadFile` | `deny` (exit 3) when file content matches USP's credential prefix list: AKIA/ASIA (AWS), AIza (Google), ghp_/gho_/ghs_ (GitHub), xox[abps]- (Slack), sk_live_/sk_test_ (Stripe), JWT shape, PEM private-key headers. Otherwise `allow` |
| `usp-block-dangerous-shell.sh` | `beforeShellExecution` | `deny` for `rm -rf /` / `rm -rf /*` / `rm -rf ~` / `rm -rf $HOME`, `curl\|sh`, `wget\|sh`, `chmod 777`, fork bombs, `dd of=/dev/sd*`. `ask` for `git filter-branch` / `git filter-repo`, force pushes, `git reset --hard`, cloud-auth commands (`aws configure`, `gcloud auth`, `kubectl config`, `docker login`), and any command touching `.aws/credentials` / `.kube/config` / `.ssh/id_*`. Otherwise `allow` |
| `usp-mcp-dial-control.sh` | `beforeMCPExecution` | Reads the HTTP egress allowlist line from `<project>/.security-pilot/PROJECT_PILOT.md`. Progressive enforcement: empty allowlist → `allow` (educational; the audit hook still records the call). Populated allowlist + URL substring match → `allow`. Populated + miss → `ask`. No URL-shaped argument in the MCP payload → `allow` (not an HTTP egress call by our heuristic) |

The Dial-Control progression maps to the natural USP onboarding: `/sec-init` creates an empty allowlist, `/ai-harden` helps you populate it, and from that point on the hook becomes real enforcement.

### Install

```bash
bash ~/.security-pilot/install.sh --wire-cursor-hooks
```

Hooks are a **separate, opt-in flag** — they change Cursor's agent behavior globally, and a malformed hook can wedge the agent loop. Re-test in Cursor after installing. The installer:

- Symlinks each `usp-*.sh` into `~/.cursor/hooks/` (so updates to USP propagate).
- Writes `~/.cursor/hooks.json` as a **real file copy** (so you can merge in your own hooks). If one already exists, it's backed up to `~/.cursor/hooks.json.bak.<ts>` first.
- Reminds you to restart Cursor afterwards.

To merge custom hooks: edit `~/.cursor/hooks.json` directly (it's a real file, not a symlink). The reference USP version stays at `~/.security-pilot/ADAPTERS/cursor/hooks/hooks.json` if you need to diff.

### Requirements

Hook scripts call `jq` to parse Cursor's JSON payloads. Install it via your package manager.

### Audit log hygiene

The audit log is per-project by default. Add this to your project's `.gitignore`:

```gitignore
.security-pilot/audit-trail.log
```

It captures every shell, MCP, and prompt-submit payload Cursor's agent fires — useful for post-hoc forensic review, never useful in version control.

---

## Equivalents in adjacent tools (no slash-command / hooks surface)

- **Continue (continue.dev)** — the `config.json` `systemMessage` field accepts the Layer 1 stanza; or use `.continuerules` if present.
- **Copilot Chat (custom instructions)** — paste the Layer 1 stanza into "Repository custom instructions" via the GitHub repo settings. Same triggers, same rules.
- **Aider** — use `.aider.conf.yml` `read:` array to auto-include `~/.security-pilot/PILOT.md` in every session.

These tools don't expose a hook surface, so the policy-as-code Layer 3 is Cursor-specific for now.

---

## Project-level integration

The `.cursorrules` reference resolves the canonical PILOT.md path on every interaction. Once `/sec-init` has been run, the rules-file reference to `<project>/.security-pilot/PROJECT_PILOT.md` becomes live — project overrides apply automatically thereafter, *and* the Dial-Control hook starts reading the project's HTTP egress allowlist from that file.
