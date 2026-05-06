#!/usr/bin/env bash
# Universal Security Pilot — installer
# https://github.com/VikingOwl91/universal-security-pilot
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/VikingOwl91/universal-security-pilot/main/install.sh | bash
#   bash install.sh [--wire-claude] [--wire-gemini-cli] [--wire-cursor] [--wire-cursor-hooks] [--wire-codex-cli] [--wire-mistral-vibe] [--wire-all] [--migrate] [--cleanup-orphans] [--yes] [--uninstall]
#
# The installer is idempotent. Re-running updates an existing checkout
# (fast-forward only) and never clobbers local changes or unrelated files.

set -Eeuo pipefail

REPO_URL="${USP_REPO_URL:-https://github.com/VikingOwl91/universal-security-pilot.git}"
INSTALL_DIR="${USP_INSTALL_DIR:-$HOME/.security-pilot}"
BRANCH="${USP_BRANCH:-main}"

if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YLW=$'\033[33m'; C_BLU=$'\033[34m'; C_RST=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YLW=""; C_BLU=""; C_RST=""
fi

log()  { printf "%s\n" "$*"; }
ok()   { printf "%s✓%s %s\n" "$C_GRN" "$C_RST" "$*"; }
warn() { printf "%s!%s %s\n" "$C_YLW" "$C_RST" "$*"; }
err()  { printf "%s✗%s %s\n" "$C_RED" "$C_RST" "$*" >&2; }
die()  { err "$*"; exit 1; }

trap 'err "Installer aborted on line $LINENO."' ERR

WIRE_CLAUDE=0
WIRE_GEMINI_CLI=0
WIRE_CURSOR=0
WIRE_CURSOR_HOOKS=0
WIRE_CODEX_CLI=0
WIRE_MISTRAL_VIBE=0
MIGRATE=0
CLEANUP_ORPHANS=0
ASSUME_YES=0
UNINSTALL=0

usage() {
  cat <<EOF
Universal Security Pilot — installer

Usage: install.sh [options]

Options:
  --wire-claude         Symlink slash commands into ~/.claude/commands (backs up existing files)
  --wire-gemini-cli     Symlink TOML custom commands into ~/.gemini/commands (backs up existing files)
  --wire-cursor         Symlink slash commands into ~/.cursor/commands (backs up existing files)
  --wire-cursor-hooks   Install agent hooks into ~/.cursor/hooks/ + ~/.cursor/hooks.json (opt-in only;
                        modifies global Cursor agent behavior. Backs up an existing hooks.json)
  --wire-codex-cli      Symlink custom prompts and skills into ~/.codex/prompts and ~/.codex/skills
  --wire-mistral-vibe   Symlink skills into ~/.vibe/skills/<name>/SKILL.md (backs up existing files)
  --wire-all            Wire every adapter whose config dir is detected under \$HOME (Claude,
                        Cursor commands, Gemini, Codex, Vibe). Skips undetected ones silently —
                        e.g. on a machine without ~/.codex, --wire-all leaves Codex alone instead
                        of warning. Does NOT include --wire-cursor-hooks (always opt-in, modifies
                        global agent behavior).
  --migrate             Convert a manually-installed (non-git) USP at \$USP_INSTALL_DIR into a
                        managed git checkout. Backs up the existing directory to <dir>.bak.<ts>
                        and clones fresh. Refuses if the directory doesn't look like USP
                        (no PILOT.md) — never auto-migrates unrelated data.
  --cleanup-orphans     Move USP-named files/dirs in tool config dirs that AREN'T on any wire
                        path the installer manages (typical: leftover content from older USP
                        versions or manual installs) to per-tool backup dirs at
                        ~/.<tool>/.usp-orphan-backup-<ts>/. Reversible (mv, never rm).
                        Only touches paths whose basename matches sec-init / sec-audit / sec-fix
                        / ai-harden / security-pilot / usp-* and that live under the wire-parent
                        dirs the installer scans (e.g. ~/.claude/skills/, ~/.codex/prompts/).
  --yes, -y             Skip interactive prompts (assume yes)
  --uninstall           Remove the installation and any symlinks it created
  -h, --help            Show this help

Environment:
  USP_INSTALL_DIR  Override install path (default: \$HOME/.security-pilot)
  USP_REPO_URL     Override repository URL
  USP_BRANCH       Override branch (default: main)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wire-claude)       WIRE_CLAUDE=1 ;;
    --wire-gemini-cli)   WIRE_GEMINI_CLI=1 ;;
    --wire-cursor)       WIRE_CURSOR=1 ;;
    --wire-cursor-hooks) WIRE_CURSOR_HOOKS=1 ;;
    --wire-codex-cli)    WIRE_CODEX_CLI=1 ;;
    --wire-mistral-vibe) WIRE_MISTRAL_VIBE=1 ;;
    --wire-all)
      # Only affects providers whose config dir is detected — keeps the flag
      # quiet on machines that don't have all five tools installed. Explicit
      # --wire-X earlier on the command line still takes effect because we
      # only set 0 → 1 here, never 1 → 0.
      [[ -d "$HOME/.claude" ]] && WIRE_CLAUDE=1
      [[ -d "$HOME/.gemini" ]] && WIRE_GEMINI_CLI=1
      [[ -d "$HOME/.cursor" ]] && WIRE_CURSOR=1
      [[ -d "$HOME/.codex"  ]] && WIRE_CODEX_CLI=1
      [[ -d "$HOME/.vibe"   ]] && WIRE_MISTRAL_VIBE=1
      # --wire-cursor-hooks is intentionally NOT enabled here; hooks change
      # global Cursor agent behavior and remain explicit-only.
      ;;
    --migrate)           MIGRATE=1 ;;
    --cleanup-orphans)   CLEANUP_ORPHANS=1 ;;
    --yes|-y)            ASSUME_YES=1 ;;
    --uninstall)         UNINSTALL=1 ;;
    -h|--help)           usage; exit 0 ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
  shift
done

# --- Safety guards ----------------------------------------------------------

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  die "Refusing to run as root. The pilot installs into \$HOME and should run as your user."
fi

if [[ -z "${HOME:-}" || ! -d "$HOME" ]]; then
  die "\$HOME is not set or not a directory."
fi

case "$INSTALL_DIR" in
  "$HOME"/*) : ;;
  *) die "USP_INSTALL_DIR must live under \$HOME (got: $INSTALL_DIR)" ;;
esac

command -v git >/dev/null 2>&1 || die "Missing required tool: git"

# --- Stanza utilities -------------------------------------------------------

strip_stanza() {
  # strip_stanza <target-file>  — remove the USP-marked block (and the file
  # if it becomes empty as a result). Idempotent. Used by --uninstall.
  local target="$1"
  [[ -f "$target" ]] || return 0

  local begin='<!-- USP:stanza:begin -->'
  local end='<!-- USP:stanza:end -->'

  grep -qF "$begin" "$target" 2>/dev/null || return 0

  local tmp
  tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '
    $0 == b { in_block = 1; next }
    $0 == e { in_block = 0; next }
    !in_block { print }
  ' "$target" > "$tmp"

  # Trim trailing blank lines we may have left behind.
  awk 'NF { keep = NR } { lines[NR] = $0 } END { for (i = 1; i <= keep; i++) print lines[i] }' "$tmp" > "${tmp}.trim"
  mv "${tmp}.trim" "$tmp"

  if [[ ! -s "$tmp" ]]; then
    rm -f "$target" "$tmp" && ok "Removed empty $target (no content remaining after stripping USP stanza)"
  else
    mv "$tmp" "$target"
    ok "Stripped USP stanza from $target"
  fi
}

# --- Uninstall --------------------------------------------------------------

remove_symlink() {
  # remove_symlink <link-path> <expected-target>
  # Idempotent: removes only if <link-path> is a symlink whose target matches exactly.
  local link="$1" expected="$2" actual
  [[ -L "$link" ]] || return 0
  actual="$(readlink "$link" 2>/dev/null || true)"
  [[ "$actual" == "$expected" ]] || return 0
  rm -f "$link" && ok "Removed symlink $link"
}

remove_claude_symlinks() {
  local name
  for name in sec-init sec-audit sec-fix ai-harden; do
    remove_symlink "$HOME/.claude/commands/${name}.md" "$INSTALL_DIR/COMMANDS/${name}.md"
  done
  for name in sec-audit sec-fix ai-harden; do
    remove_symlink "$HOME/.claude/skills/${name}.md" "$INSTALL_DIR/SKILLS/${name}.md"
  done
}

remove_gemini_cli_symlinks() {
  local name
  for name in sec-init sec-audit sec-fix ai-harden; do
    remove_symlink "$HOME/.gemini/commands/${name}.toml" "$INSTALL_DIR/ADAPTERS/gemini-cli/commands/${name}.toml"
  done
}

remove_codex_cli_symlinks() {
  local name
  for name in sec-init sec-audit sec-fix ai-harden; do
    remove_symlink "$HOME/.codex/prompts/${name}.md" "$INSTALL_DIR/ADAPTERS/codex-cli/prompts/${name}.md"
  done
  for name in sec-audit sec-fix ai-harden; do
    remove_symlink "$HOME/.codex/skills/${name}/SKILL.md" "$INSTALL_DIR/ADAPTERS/codex-cli/skills/${name}/SKILL.md"
    rmdir "$HOME/.codex/skills/${name}" 2>/dev/null || true
  done
}

remove_mistral_vibe_symlinks() {
  local name
  for name in sec-init sec-audit sec-fix ai-harden; do
    remove_symlink "$HOME/.vibe/skills/${name}/SKILL.md" "$INSTALL_DIR/ADAPTERS/mistral-vibe/skills/${name}/SKILL.md"
    rmdir "$HOME/.vibe/skills/${name}" 2>/dev/null || true
  done
}

remove_cursor_symlinks() {
  local name
  for name in sec-init sec-audit sec-fix ai-harden; do
    remove_symlink "$HOME/.cursor/commands/${name}.md" "$INSTALL_DIR/COMMANDS/${name}.md"
  done
  for name in usp-audit usp-redact-secrets usp-block-dangerous-shell usp-mcp-dial-control; do
    remove_symlink "$HOME/.cursor/hooks/${name}.sh" "$INSTALL_DIR/ADAPTERS/cursor/hooks/${name}.sh"
  done
  # ~/.cursor/hooks.json is intentionally left in place — it's a real file the
  # user may have customized after USP wrote it. They can remove it manually.
  if [[ -f "$HOME/.cursor/hooks.json" ]]; then
    # shellcheck disable=SC2088  # tilde is intentional display text, not a path to expand
    warn "~/.cursor/hooks.json left in place (may have user customizations). Remove manually if no longer needed."
  fi
}

if [[ "$UNINSTALL" -eq 1 ]]; then
  log "Uninstalling Universal Security Pilot..."
  remove_claude_symlinks
  remove_gemini_cli_symlinks
  remove_codex_cli_symlinks
  remove_mistral_vibe_symlinks
  remove_cursor_symlinks
  strip_stanza "$HOME/.claude/CLAUDE.md"
  strip_stanza "$HOME/.gemini/GEMINI.md"
  strip_stanza "$HOME/.codex/AGENTS.md"
  strip_stanza "$HOME/.vibe/AGENTS.md"
  if [[ -d "$INSTALL_DIR" ]]; then
    if [[ -d "$INSTALL_DIR/.git" ]]; then
      rm -rf "$INSTALL_DIR" && ok "Removed $INSTALL_DIR"
    else
      die "$INSTALL_DIR is not a git checkout — refusing to delete. Remove it manually."
    fi
  else
    log "(nothing to remove at $INSTALL_DIR)"
  fi
  ok "Uninstall complete."
  exit 0
fi

# --- Install / update -------------------------------------------------------

log "${C_BLU}Universal Security Pilot — installer${C_RST}"
log ""
log "  Install dir: $INSTALL_DIR"
log "  Repo URL:    $REPO_URL"
log "  Branch:      $BRANCH"
log ""

# Migrate a non-git installation (manual setup, older non-installer drop, etc.)
# into a managed git checkout. Only runs with explicit --migrate; refuses if the
# directory doesn't look like USP (no PILOT.md) so we never destructively rename
# unrelated user data that happens to live at the install path.
if [[ -e "$INSTALL_DIR" && ! -d "$INSTALL_DIR/.git" ]]; then
  if [[ "$MIGRATE" -ne 1 ]]; then
    err "$INSTALL_DIR exists but is not a git checkout."
    log ""
    log "This usually means USP was installed manually (not via this installer)."
    log "To migrate it to a managed git checkout, re-run with --migrate:"
    log ""
    log "  curl -fsSL https://raw.githubusercontent.com/VikingOwl91/universal-security-pilot/main/install.sh \\"
    log "    | bash -s -- --migrate"
    log ""
    log "Or, if you've cloned the installer locally:  bash install.sh --migrate"
    log ""
    log "Migration will:"
    log "  1. Move the existing directory to ${INSTALL_DIR}.bak.<timestamp>"
    log "  2. Clone the latest into $INSTALL_DIR"
    log "  3. Leave the backup in place for you to inspect (delete when satisfied)"
    exit 1
  fi

  [[ -f "$INSTALL_DIR/PILOT.md" ]] \
    || die "$INSTALL_DIR exists but doesn't look like a USP installation (no PILOT.md). Refusing to migrate unrelated data; move it aside manually before re-running."

  backup="${INSTALL_DIR}.bak.$(date +%s)"
  mv "$INSTALL_DIR" "$backup"
  ok "Migrated existing non-git installation: $INSTALL_DIR → $backup"
  log "  Inspect or remove the backup with: rm -rf '$backup'"
  log ""
fi

if [[ -e "$INSTALL_DIR" ]]; then
  log "Updating existing installation..."
  git -C "$INSTALL_DIR" remote get-url origin >/dev/null 2>&1 \
    || die "$INSTALL_DIR has no 'origin' remote."

  git -C "$INSTALL_DIR" fetch --quiet origin "$BRANCH" \
    || die "git fetch failed (network or branch issue)"

  if ! git -C "$INSTALL_DIR" diff --quiet || ! git -C "$INSTALL_DIR" diff --cached --quiet; then
    warn "Local changes detected in $INSTALL_DIR — skipping pull (your edits are preserved)."
  else
    if git -C "$INSTALL_DIR" merge-base --is-ancestor HEAD "origin/$BRANCH"; then
      git -C "$INSTALL_DIR" merge --ff-only "origin/$BRANCH" --quiet \
        || die "Fast-forward failed; resolve manually with: git -C $INSTALL_DIR status"
      ok "Updated to $(git -C "$INSTALL_DIR" rev-parse --short HEAD)"
    else
      warn "Local HEAD has diverged from origin/$BRANCH — skipping pull."
    fi
  fi
else
  log "Cloning..."
  git clone --depth=1 --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR" --quiet \
    || die "git clone failed (network, auth, or branch issue)"
  ok "Cloned to $INSTALL_DIR"
fi

# Sanity check: confirm the canonical files are present.
REQUIRED_FILES=(
  "PILOT.md"
  "SKILLS/sec-audit.md"
  "SKILLS/sec-fix.md"
  "SKILLS/ai-harden.md"
  "COMMANDS/sec-init.md"
  "COMMANDS/sec-audit.md"
  "COMMANDS/sec-fix.md"
  "COMMANDS/ai-harden.md"
  "ADAPTERS/claude-code.md"
  "ADAPTERS/cursor.md"
  "ADAPTERS/gemini-cli.md"
  "ADAPTERS/gemini-cli/commands/sec-init.toml"
  "ADAPTERS/gemini-cli/commands/sec-audit.toml"
  "ADAPTERS/gemini-cli/commands/sec-fix.toml"
  "ADAPTERS/gemini-cli/commands/ai-harden.toml"
  "ADAPTERS/cursor/hooks/hooks.json"
  "ADAPTERS/cursor/hooks/usp-audit.sh"
  "ADAPTERS/cursor/hooks/usp-redact-secrets.sh"
  "ADAPTERS/cursor/hooks/usp-block-dangerous-shell.sh"
  "ADAPTERS/cursor/hooks/usp-mcp-dial-control.sh"
  "ADAPTERS/codex-cli.md"
  "ADAPTERS/codex-cli/prompts/sec-init.md"
  "ADAPTERS/codex-cli/prompts/sec-audit.md"
  "ADAPTERS/codex-cli/prompts/sec-fix.md"
  "ADAPTERS/codex-cli/prompts/ai-harden.md"
  "ADAPTERS/codex-cli/skills/sec-audit/SKILL.md"
  "ADAPTERS/codex-cli/skills/sec-fix/SKILL.md"
  "ADAPTERS/codex-cli/skills/ai-harden/SKILL.md"
  "ADAPTERS/mistral-vibe.md"
  "ADAPTERS/mistral-vibe/skills/sec-init/SKILL.md"
  "ADAPTERS/mistral-vibe/skills/sec-audit/SKILL.md"
  "ADAPTERS/mistral-vibe/skills/sec-fix/SKILL.md"
  "ADAPTERS/mistral-vibe/skills/ai-harden/SKILL.md"
  "ADAPTERS/claude-code/stanza.md"
  "ADAPTERS/cursor/stanza.md"
  "ADAPTERS/gemini-cli/stanza.md"
  "ADAPTERS/codex-cli/stanza.md"
  "ADAPTERS/mistral-vibe/stanza.md"
  "REFERENCE/framework-footguns.md"
)
for f in "${REQUIRED_FILES[@]}"; do
  [[ -f "$INSTALL_DIR/$f" ]] || die "Sanity check failed: missing $INSTALL_DIR/$f"
done
ok "Sanity check passed (${#REQUIRED_FILES[@]} files verified)."

# --- Optional: wire Claude Code slash commands ------------------------------

link_one() {
  # link_one <src> <dst> <label>  — idempotent symlink with backup of existing files.
  local src="$1" dst="$2" label="$3" existing backup
  [[ -f "$src" ]] || { warn "Source $src missing, skipping"; return 0; }

  if [[ -L "$dst" ]]; then
    existing="$(readlink "$dst")"
    if [[ "$existing" == "$src" ]]; then
      ok "$label already linked"
      return 0
    fi
  fi
  if [[ -e "$dst" ]]; then
    backup="${dst}.bak.$(date +%s)"
    cp -p "$dst" "$backup"
    ok "Backed up $dst → $backup"
    rm -f "$dst"
  fi
  ln -s "$src" "$dst"
  ok "Linked $label → $src"
}

append_or_update_stanza() {
  # append_or_update_stanza <target-file> <stanza-source> <label>
  # Idempotently maintains a USP-marked block at the end of <target-file>.
  # Strips any existing block between USP markers, then appends a fresh
  # block from <stanza-source>. Anything outside the markers is preserved.
  local target="$1" src="$2" label="$3"
  [[ -f "$src" ]] || { warn "Stanza source $src missing, skipping $label"; return 0; }

  local begin='<!-- USP:stanza:begin -->'
  local end='<!-- USP:stanza:end -->'
  local tmp
  tmp="$(mktemp)"

  if [[ -f "$target" ]]; then
    awk -v b="$begin" -v e="$end" '
      $0 == b { in_block = 1; next }
      $0 == e { in_block = 0; next }
      !in_block { print }
    ' "$target" > "$tmp"
  fi

  if [[ -s "$tmp" ]]; then
    # Ensure there's a blank line separator before our block.
    if [[ "$(tail -c1 "$tmp" 2>/dev/null || true)" != "" ]]; then
      printf '\n' >> "$tmp"
    fi
    printf '\n' >> "$tmp"
  fi

  {
    printf '%s\n' "$begin"
    printf '%s\n' '<!-- DO NOT EDIT BETWEEN THESE MARKERS — managed by ~/.security-pilot/install.sh -->'
    cat "$src"
    printf '%s\n' "$end"
  } >> "$tmp"

  mkdir -p "$(dirname "$target")" 2>/dev/null || true
  mv "$tmp" "$target"
  ok "Stanza synced → $target ($label)"
}

offer_wire() {
  # offer_wire <force-flag-int> <home-subdir> <wire-fn-name> <wire-flag> <description>
  #
  # Decision tree:
  #   force-flag set    → run wire fn unconditionally (it handles a missing config dir itself)
  #   subdir absent     → silent no-op (nothing to wire)
  #   --yes (ASSUME_YES) → run wire fn
  #   interactive (tty) → prompt y/N
  #   non-interactive   → print re-run hint
  local force="$1" subdir="$2" wire_fn="$3" flag="$4" desc="$5" ans
  if [[ "$force" -eq 1 ]]; then
    "$wire_fn"
    return 0
  fi
  [[ -d "$HOME/$subdir" ]] || return 0
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    "$wire_fn"
  elif [[ -t 0 && -t 1 ]]; then
    read -r -p "Detected ~/$subdir — wire $desc? [y/N] " ans
    case "$ans" in
      [yY]|[yY][eE][sS]) "$wire_fn" ;;
      *) log "(skipped — re-run with $flag to enable later)" ;;
    esac
  else
    log ""
    log "Detected ~/$subdir. To wire $desc, re-run with:"
    log "  bash $INSTALL_DIR/install.sh $flag"
  fi
}

wire_claude() {
  if [[ ! -d "$HOME/.claude" ]]; then
    # shellcheck disable=SC2088  # tilde is intentional display text, not a path to expand
    warn "~/.claude not found — skipping Claude Code wiring (is Claude Code installed?)."
    return 0
  fi
  local cdir="$HOME/.claude/commands"
  local sdir="$HOME/.claude/skills"
  mkdir -p "$cdir" "$sdir"

  local name
  for name in sec-init sec-audit sec-fix ai-harden; do
    link_one "$INSTALL_DIR/COMMANDS/${name}.md" "$cdir/${name}.md" "/$name"
  done
  for name in sec-audit sec-fix ai-harden; do
    link_one "$INSTALL_DIR/SKILLS/${name}.md" "$sdir/${name}.md" "skill:$name"
  done

  append_or_update_stanza "$HOME/.claude/CLAUDE.md" \
    "$INSTALL_DIR/ADAPTERS/claude-code/stanza.md" "claude-code"

  log ""
  log "Note: Claude Code's autonomous Skill discovery activates after a session restart."
  log "Slash commands (/sec-audit, /sec-fix, /ai-harden, /sec-init) work immediately."
}

offer_wire "$WIRE_CLAUDE" ".claude" wire_claude --wire-claude "slash commands into Claude Code"

# --- Optional: wire Gemini CLI custom commands ------------------------------

wire_gemini_cli() {
  if [[ ! -d "$HOME/.gemini" ]]; then
    # shellcheck disable=SC2088  # tilde is intentional display text, not a path to expand
    warn "~/.gemini not found — skipping Gemini CLI wiring (is Gemini CLI installed?)."
    return 0
  fi
  local cdir="$HOME/.gemini/commands"
  mkdir -p "$cdir"

  local name
  for name in sec-init sec-audit sec-fix ai-harden; do
    link_one "$INSTALL_DIR/ADAPTERS/gemini-cli/commands/${name}.toml" "$cdir/${name}.toml" "/$name"
  done

  append_or_update_stanza "$HOME/.gemini/GEMINI.md" \
    "$INSTALL_DIR/ADAPTERS/gemini-cli/stanza.md" "gemini-cli"

  log ""
  log "Note: in Gemini CLI, run /commands reload to pick up the new commands without restarting."
}

offer_wire "$WIRE_GEMINI_CLI" ".gemini" wire_gemini_cli --wire-gemini-cli "TOML custom commands into Gemini CLI"

# --- Optional: wire Cursor slash commands -----------------------------------

wire_cursor() {
  if [[ ! -d "$HOME/.cursor" ]]; then
    # shellcheck disable=SC2088  # tilde is intentional display text, not a path to expand
    warn "~/.cursor not found — skipping Cursor wiring (is Cursor installed?)."
    return 0
  fi
  local cdir="$HOME/.cursor/commands"
  mkdir -p "$cdir"

  local name
  for name in sec-init sec-audit sec-fix ai-harden; do
    link_one "$INSTALL_DIR/COMMANDS/${name}.md" "$cdir/${name}.md" "/$name"
  done

  log ""
  log "Note: type / in Cursor's chat to surface the new commands."
}

offer_wire "$WIRE_CURSOR" ".cursor" wire_cursor --wire-cursor "slash commands into Cursor"

# --- Optional: wire Cursor agent hooks (opt-in, no interactive offer) -------
# Hooks change global Cursor agent behavior — always require an explicit flag.

wire_cursor_hooks() {
  if [[ ! -d "$HOME/.cursor" ]]; then
    # shellcheck disable=SC2088  # tilde is intentional display text, not a path to expand
    warn "~/.cursor not found — skipping Cursor hooks wiring (is Cursor installed?)."
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found in PATH — Cursor hook scripts require jq to parse payloads."
    warn "Install jq via your package manager, then re-run --wire-cursor-hooks."
    return 0
  fi

  local hdir="$HOME/.cursor/hooks"
  mkdir -p "$hdir"

  local name
  for name in usp-audit usp-redact-secrets usp-block-dangerous-shell usp-mcp-dial-control; do
    chmod +x "$INSTALL_DIR/ADAPTERS/cursor/hooks/${name}.sh" 2>/dev/null || true
    link_one "$INSTALL_DIR/ADAPTERS/cursor/hooks/${name}.sh" "$hdir/${name}.sh" "hook:$name"
  done

  # hooks.json is a real file (not a symlink) so the user can merge in their
  # own hooks. Back up an existing one before overwriting.
  local hooks_json="$HOME/.cursor/hooks.json"
  local hooks_src="$INSTALL_DIR/ADAPTERS/cursor/hooks/hooks.json"
  if [[ -e "$hooks_json" && ! -L "$hooks_json" ]]; then
    local backup
    backup="${hooks_json}.bak.$(date +%s)"
    cp -p "$hooks_json" "$backup"
    ok "Backed up existing $hooks_json → $backup"
    warn "If your previous hooks.json had custom hooks, merge them into the new $hooks_json by hand."
  elif [[ -L "$hooks_json" ]]; then
    rm -f "$hooks_json"
  fi
  cp "$hooks_src" "$hooks_json"
  ok "Wrote $hooks_json (USP reference config; safe to edit / extend)"

  log ""
  log "Note: restart Cursor to load the new hooks. Tail your project's"
  log ".security-pilot/audit-trail.log to verify hook activity."
}

if [[ "$WIRE_CURSOR_HOOKS" -eq 1 ]]; then
  wire_cursor_hooks
fi

# --- Optional: wire Codex CLI custom prompts and skills ---------------------

wire_codex_cli() {
  if [[ ! -d "$HOME/.codex" ]]; then
    # shellcheck disable=SC2088  # tilde is intentional display text, not a path to expand
    warn "~/.codex not found — skipping Codex CLI wiring (is Codex CLI installed?)."
    return 0
  fi
  local pdir="$HOME/.codex/prompts"
  local sdir="$HOME/.codex/skills"
  mkdir -p "$pdir" "$sdir"

  local name
  for name in sec-init sec-audit sec-fix ai-harden; do
    link_one "$INSTALL_DIR/ADAPTERS/codex-cli/prompts/${name}.md" "$pdir/${name}.md" "/prompts:$name"
  done
  for name in sec-audit sec-fix ai-harden; do
    mkdir -p "$sdir/${name}"
    link_one "$INSTALL_DIR/ADAPTERS/codex-cli/skills/${name}/SKILL.md" "$sdir/${name}/SKILL.md" "skill:\$$name"
  done

  append_or_update_stanza "$HOME/.codex/AGENTS.md" \
    "$INSTALL_DIR/ADAPTERS/codex-cli/stanza.md" "codex-cli"

  log ""
  log "Note: Codex CLI loads custom prompts only at startup — restart Codex to surface"
  log "the new /prompts:* commands. Skills auto-discover."
}

offer_wire "$WIRE_CODEX_CLI" ".codex" wire_codex_cli --wire-codex-cli "custom prompts and skills into Codex CLI"

# --- Optional: wire Mistral Vibe skills -------------------------------------

wire_mistral_vibe() {
  if [[ ! -d "$HOME/.vibe" ]]; then
    # shellcheck disable=SC2088  # tilde is intentional display text, not a path to expand
    warn "~/.vibe not found — skipping Mistral Vibe wiring (is Mistral Vibe installed?)."
    return 0
  fi
  local sdir="$HOME/.vibe/skills"
  mkdir -p "$sdir"

  local name
  for name in sec-init sec-audit sec-fix ai-harden; do
    mkdir -p "$sdir/${name}"
    link_one "$INSTALL_DIR/ADAPTERS/mistral-vibe/skills/${name}/SKILL.md" "$sdir/${name}/SKILL.md" "skill:/$name"
  done

  append_or_update_stanza "$HOME/.vibe/AGENTS.md" \
    "$INSTALL_DIR/ADAPTERS/mistral-vibe/stanza.md" "mistral-vibe"

  log ""
  log "Note: Mistral Vibe auto-discovers skills at startup — restart Vibe to surface"
  log "the new /sec-init, /sec-audit, /sec-fix, and /ai-harden commands in autocomplete."
}

offer_wire "$WIRE_MISTRAL_VIBE" ".vibe" wire_mistral_vibe --wire-mistral-vibe "skills into Mistral Vibe"

# --- Detection summary + suggested next steps -------------------------------

# Single source of truth for "what this installer wires where". Each row:
#   tool|target-relpath-from-HOME|canonical-relpath-from-INSTALL_DIR
# Used by drift detection in the post-install summary.
WIRE_TARGETS=(
  "claude|.claude/commands/sec-init.md|COMMANDS/sec-init.md"
  "claude|.claude/commands/sec-audit.md|COMMANDS/sec-audit.md"
  "claude|.claude/commands/sec-fix.md|COMMANDS/sec-fix.md"
  "claude|.claude/commands/ai-harden.md|COMMANDS/ai-harden.md"
  "claude|.claude/skills/sec-audit.md|SKILLS/sec-audit.md"
  "claude|.claude/skills/sec-fix.md|SKILLS/sec-fix.md"
  "claude|.claude/skills/ai-harden.md|SKILLS/ai-harden.md"
  "gemini|.gemini/commands/sec-init.toml|ADAPTERS/gemini-cli/commands/sec-init.toml"
  "gemini|.gemini/commands/sec-audit.toml|ADAPTERS/gemini-cli/commands/sec-audit.toml"
  "gemini|.gemini/commands/sec-fix.toml|ADAPTERS/gemini-cli/commands/sec-fix.toml"
  "gemini|.gemini/commands/ai-harden.toml|ADAPTERS/gemini-cli/commands/ai-harden.toml"
  "cursor-cmds|.cursor/commands/sec-init.md|COMMANDS/sec-init.md"
  "cursor-cmds|.cursor/commands/sec-audit.md|COMMANDS/sec-audit.md"
  "cursor-cmds|.cursor/commands/sec-fix.md|COMMANDS/sec-fix.md"
  "cursor-cmds|.cursor/commands/ai-harden.md|COMMANDS/ai-harden.md"
  "cursor-hooks|.cursor/hooks/usp-audit.sh|ADAPTERS/cursor/hooks/usp-audit.sh"
  "cursor-hooks|.cursor/hooks/usp-redact-secrets.sh|ADAPTERS/cursor/hooks/usp-redact-secrets.sh"
  "cursor-hooks|.cursor/hooks/usp-block-dangerous-shell.sh|ADAPTERS/cursor/hooks/usp-block-dangerous-shell.sh"
  "cursor-hooks|.cursor/hooks/usp-mcp-dial-control.sh|ADAPTERS/cursor/hooks/usp-mcp-dial-control.sh"
  "codex|.codex/prompts/sec-init.md|ADAPTERS/codex-cli/prompts/sec-init.md"
  "codex|.codex/prompts/sec-audit.md|ADAPTERS/codex-cli/prompts/sec-audit.md"
  "codex|.codex/prompts/sec-fix.md|ADAPTERS/codex-cli/prompts/sec-fix.md"
  "codex|.codex/prompts/ai-harden.md|ADAPTERS/codex-cli/prompts/ai-harden.md"
  "codex|.codex/skills/sec-audit/SKILL.md|ADAPTERS/codex-cli/skills/sec-audit/SKILL.md"
  "codex|.codex/skills/sec-fix/SKILL.md|ADAPTERS/codex-cli/skills/sec-fix/SKILL.md"
  "codex|.codex/skills/ai-harden/SKILL.md|ADAPTERS/codex-cli/skills/ai-harden/SKILL.md"
  "vibe|.vibe/skills/sec-init/SKILL.md|ADAPTERS/mistral-vibe/skills/sec-init/SKILL.md"
  "vibe|.vibe/skills/sec-audit/SKILL.md|ADAPTERS/mistral-vibe/skills/sec-audit/SKILL.md"
  "vibe|.vibe/skills/sec-fix/SKILL.md|ADAPTERS/mistral-vibe/skills/sec-fix/SKILL.md"
  "vibe|.vibe/skills/ai-harden/SKILL.md|ADAPTERS/mistral-vibe/skills/ai-harden/SKILL.md"
)

is_drifted() {
  # Returns 0 (true) if a USP-managed wire path exists but isn't the expected
  # canonical symlink — i.e. it's a regular file (manual install), a broken
  # symlink, or a symlink pointing at the wrong target.
  local target="$1" expected="$2"
  if [[ -L "$target" ]]; then
    [[ "$(readlink "$target")" != "$expected" ]]
  elif [[ -e "$target" ]]; then
    return 0
  else
    return 1
  fi
}

count_drift() {
  # count_drift <tool>  → echoes the count of drifted wire paths for that tool.
  local tool="$1" n=0 row trel can
  for row in "${WIRE_TARGETS[@]}"; do
    [[ "${row%%|*}" == "$tool" ]] || continue
    trel="${row#*|}"; trel="${trel%%|*}"
    can="${row##*|}"
    if is_drifted "$HOME/$trel" "$INSTALL_DIR/$can"; then
      n=$((n+1))
    fi
  done
  echo "$n"
  return 0
}

# --- Orphan detection -------------------------------------------------------
#
# An orphan is a path that:
#   1. Lives directly under a USP wire-parent dir (commands/, skills/, etc.)
#   2. Has a basename that looks USP-shaped (USP_NAMES_REGEX)
#   3. Is NOT itself a wire target AND is not a parent dir of one
#
# Common cause: leftover content from older USP versions or manual installs
# (e.g., ~/.claude/skills/sec-audit/ subdir from a pre-installer setup, when
# the installer wires ~/.claude/skills/sec-audit.md as a file).

# Wire-parent dirs scanned for orphans. Each row: tool|parent-relpath.
WIRE_PARENTS=(
  "claude|.claude/commands"
  "claude|.claude/skills"
  "cursor|.cursor/commands"
  "cursor|.cursor/hooks"
  "gemini|.gemini/commands"
  "codex|.codex/prompts"
  "codex|.codex/skills"
  "vibe|.vibe/skills"
)

# Names that look like USP content. Matches the canonical short names plus
# anything starting with `usp-` (covers hook scripts). Optional .ext suffix
# (must be all-lowercase letters; doesn't match .bak.<digits> backups).
USP_NAMES_REGEX='^(sec-init|sec-audit|sec-fix|ai-harden|security-pilot|usp-[a-z-]+)(\.[a-z]+)?$'

is_wire_target_or_parent() {
  # is_wire_target_or_parent <tool> <relpath>
  # 0 (true) if <relpath> is a wire target for <tool>, or the parent dir of one.
  # Prefix-matches the tool key in WIRE_TARGETS — so calling with "cursor"
  # matches both "cursor-cmds" and "cursor-hooks" rows, which is what
  # orphan detection needs (it scans all surfaces of a tool together).
  local tool="$1" relpath="$2" row row_tool trel
  for row in "${WIRE_TARGETS[@]}"; do
    row_tool="${row%%|*}"
    [[ "$row_tool" == "$tool" || "$row_tool" == "${tool}-"* ]] || continue
    trel="${row#*|}"; trel="${trel%%|*}"
    [[ "$trel" == "$relpath" ]] && return 0
    [[ "$trel" == "${relpath}/"* ]] && return 0
  done
  return 1
}

find_orphans() {
  # find_orphans <tool>  → echoes one orphan absolute path per line.
  local tool="$1" parent_relpath full_parent entry name relpath row
  for row in "${WIRE_PARENTS[@]}"; do
    [[ "${row%%|*}" == "$tool" ]] || continue
    parent_relpath="${row#*|}"
    full_parent="$HOME/$parent_relpath"
    [[ -d "$full_parent" ]] || continue
    # Glob doesn't match dotfiles by default — that protects our own
    # .usp-orphan-backup-<ts>/ dirs from being flagged.
    shopt -s nullglob
    for entry in "$full_parent"/*; do
      name="$(basename "$entry")"
      [[ "$name" =~ $USP_NAMES_REGEX ]] || continue
      relpath="$parent_relpath/$name"
      if is_wire_target_or_parent "$tool" "$relpath"; then
        continue
      fi
      printf '%s\n' "$entry"
    done
    shopt -u nullglob
  done
  return 0
}

count_orphans() {
  # count_orphans <tool>  → echoes the count of orphan paths.
  find_orphans "$1" | wc -l | tr -d ' '
  return 0
}

cleanup_orphans() {
  # Move every orphan to ~/.<tool>/.usp-orphan-backup-<ts>/. Never deletes.
  local ts tool entry backup_root name total=0
  ts=$(date +%s)
  for tool in claude cursor gemini codex vibe; do
    local subdir
    case "$tool" in
      claude) subdir=".claude" ;;
      cursor) subdir=".cursor" ;;
      gemini) subdir=".gemini" ;;
      codex)  subdir=".codex" ;;
      vibe)   subdir=".vibe" ;;
    esac
    backup_root="$HOME/$subdir/.usp-orphan-backup-$ts"
    while IFS= read -r entry; do
      [[ -n "$entry" ]] || continue
      mkdir -p "$backup_root"
      name="$(basename "$entry")"
      mv "$entry" "$backup_root/$name"
      ok "Moved orphan: $entry → $backup_root/$name"
      total=$((total+1))
    done < <(find_orphans "$tool")
  done
  log ""
  if [[ $total -eq 0 ]]; then
    log "No orphans found — all USP-shaped paths under managed wire-parent dirs are wire targets."
  else
    log "$total orphan path(s) moved to per-tool backups under ~/.{claude,cursor,gemini,codex,vibe}/.usp-orphan-backup-$ts/"
    log "Inspect, then delete with:  rm -rf ~/.{claude,cursor,gemini,codex,vibe}/.usp-orphan-backup-$ts"
  fi
}

print_status_line() {
  # print_status_line <label> <bin?> <dir?> <wired?> <wire-hint> [drift-count] [orphan-count]
  local label="$1" bin="$2" dir="$3" wired="$4" hint="$5" drift="${6:-0}" orphans="${7:-0}"
  local extras=""
  if [[ $drift -gt 0 ]]; then
    extras+=$(printf ', %s!%s %d unmanaged file(s)' "$C_YLW" "$C_RST" "$drift")
  fi
  if [[ $orphans -gt 0 ]]; then
    extras+=$(printf ', %s!%s %d orphan path(s)' "$C_YLW" "$C_RST" "$orphans")
  fi
  if [[ $bin -eq 1 && $dir -eq 1 ]]; then
    if [[ $wired -eq 1 ]]; then
      printf '  %s✓%s %-22s — %swired%s%s\n' "$C_GRN" "$C_RST" "$label" "$C_GRN" "$C_RST" "$extras"
    else
      printf '  %s✓%s %-22s — not wired (%s)%s\n' "$C_GRN" "$C_RST" "$label" "$hint" "$extras"
    fi
  elif [[ $bin -eq 1 ]]; then
    printf '  %s!%s %-22s — binary present, config dir missing (run the CLI once to initialize)\n' "$C_YLW" "$C_RST" "$label"
  elif [[ $dir -eq 1 ]]; then
    printf '  %s!%s %-22s — config dir present, binary not in PATH%s\n' "$C_YLW" "$C_RST" "$label" "$extras"
  else
    printf '  − %-22s — not detected\n' "$label"
  fi
}

# Suggestions and per-tool counts accumulate in these globals as we walk the rows below.
suggested_wires=()
total_orphans=0

detect_simple_adapter() {
  # detect_simple_adapter <label> <bin> <home-subdir> <wired-marker> <wire-flag> <drift-tool> [orphan-tool]
  # Prints one status line (with drift + orphan counts); appends to
  # $suggested_wires if detected-but-unwired OR detected-with-drift, and to
  # $total_orphans accumulator if orphans found.
  local label="$1" bin="$2" subdir="$3" marker="$4" flag="$5" drift_tool="$6"
  local orphan_tool="${7:-$drift_tool}"
  local bin_present=0 dir_present=0 wired=0 drift orphans
  command -v "$bin" >/dev/null 2>&1 && bin_present=1
  [[ -d "$HOME/$subdir" ]] && dir_present=1
  [[ -L "$HOME/$marker" ]] && wired=1
  drift=$(count_drift "$drift_tool")
  orphans=$(count_orphans "$orphan_tool")
  print_status_line "$label" "$bin_present" "$dir_present" "$wired" "run $flag" "$drift" "$orphans"
  if [[ $bin_present -eq 1 && $dir_present -eq 1 ]]; then
    if [[ $wired -eq 0 ]]; then
      suggested_wires+=("$flag")
    elif [[ $drift -gt 0 ]]; then
      suggested_wires+=("$flag    # refresh $drift unmanaged file(s)")
    fi
  fi
  total_orphans=$((total_orphans + orphans))
}

# Run cleanup_orphans BEFORE the detection summary so the post-cleanup state
# is what the user sees. Falls through silently if --cleanup-orphans wasn't passed.
if [[ "$CLEANUP_ORPHANS" -eq 1 ]]; then
  log ""
  log "${C_BLU}Cleaning up orphan paths${C_RST}"
  cleanup_orphans
fi

log ""
log "${C_BLU}Detected tools${C_RST}"
detect_simple_adapter "Claude Code" claude .claude .claude/commands/sec-init.md --wire-claude claude

# Cursor is special: two independent wires (commands + hooks). Hand-rolled status.
cursor_bin=0; cursor_dir=0; cursor_cmds_wired=0; cursor_hooks_wired=0
command -v cursor >/dev/null 2>&1 && cursor_bin=1
[[ -d "$HOME/.cursor" ]]               && cursor_dir=1
[[ -L "$HOME/.cursor/commands/sec-init.md" ]] && cursor_cmds_wired=1
[[ -L "$HOME/.cursor/hooks/usp-audit.sh"   ]] && cursor_hooks_wired=1
cursor_cmds_drift=$(count_drift "cursor-cmds")
cursor_hooks_drift=$(count_drift "cursor-hooks")
cursor_orphans=$(count_orphans "cursor")
cursor_extras=""
if [[ $cursor_cmds_drift -gt 0 || $cursor_hooks_drift -gt 0 ]]; then
  cursor_extras+=$(printf ', %s!%s %d unmanaged file(s)' "$C_YLW" "$C_RST" $((cursor_cmds_drift + cursor_hooks_drift)))
fi
if [[ $cursor_orphans -gt 0 ]]; then
  cursor_extras+=$(printf ', %s!%s %d orphan path(s)' "$C_YLW" "$C_RST" "$cursor_orphans")
fi
if [[ $cursor_bin -eq 1 && $cursor_dir -eq 1 ]]; then
  if [[ $cursor_cmds_wired -eq 1 ]]; then
    if [[ $cursor_hooks_wired -eq 1 ]]; then
      printf '  %s✓%s %-22s — %swired%s (commands + hooks)%s\n' "$C_GRN" "$C_RST" "Cursor" "$C_GRN" "$C_RST" "$cursor_extras"
    else
      printf '  %s✓%s %-22s — commands %swired%s, hooks not wired (--wire-cursor-hooks for policy enforcement)%s\n' "$C_GRN" "$C_RST" "Cursor" "$C_GRN" "$C_RST" "$cursor_extras"
    fi
  else
    printf '  %s✓%s %-22s — not wired (run --wire-cursor)%s\n' "$C_GRN" "$C_RST" "Cursor" "$cursor_extras"
  fi
else
  print_status_line "Cursor" "$cursor_bin" "$cursor_dir" 0 "run --wire-cursor" $((cursor_cmds_drift + cursor_hooks_drift)) "$cursor_orphans"
fi
[[ $cursor_bin -eq 1 && $cursor_dir -eq 1 && $cursor_cmds_wired  -eq 0 ]] && suggested_wires+=("--wire-cursor             # slash commands")
[[ $cursor_bin -eq 1 && $cursor_dir -eq 1 && $cursor_hooks_wired -eq 0 ]] && suggested_wires+=("--wire-cursor-hooks       # opt-in: policy enforcement (jq required)")
if [[ $cursor_bin -eq 1 && $cursor_dir -eq 1 ]]; then
  if [[ $cursor_cmds_wired -eq 1 && $cursor_cmds_drift -gt 0 ]]; then
    suggested_wires+=("--wire-cursor             # refresh $cursor_cmds_drift unmanaged command file(s)")
  fi
  if [[ $cursor_hooks_wired -eq 1 && $cursor_hooks_drift -gt 0 ]]; then
    suggested_wires+=("--wire-cursor-hooks       # refresh $cursor_hooks_drift unmanaged hook file(s)")
  fi
fi
total_orphans=$((total_orphans + cursor_orphans))

detect_simple_adapter "Gemini CLI"   gemini .gemini .gemini/commands/sec-init.toml  --wire-gemini-cli   gemini
detect_simple_adapter "Codex CLI"    codex  .codex  .codex/prompts/sec-init.md      --wire-codex-cli    codex
detect_simple_adapter "Mistral Vibe" vibe   .vibe   .vibe/skills/sec-init/SKILL.md  --wire-mistral-vibe vibe

if [[ $total_orphans -gt 0 && "$CLEANUP_ORPHANS" -ne 1 ]]; then
  suggested_wires+=("--cleanup-orphans         # move $total_orphans USP-shaped path(s) outside wire targets to per-tool backup dirs")
fi

if [[ ${#suggested_wires[@]} -gt 0 ]]; then
  log ""
  log "${C_BLU}Suggested next steps${C_RST}"
  for s in "${suggested_wires[@]}"; do
    log "  bash $INSTALL_DIR/install.sh $s"
  done
fi

# --- Done -------------------------------------------------------------------

log ""
ok "Universal Security Pilot installed at $INSTALL_DIR"
log ""
log "${C_BLU}Adapter docs${C_RST}"
log "  • Claude Code:  $INSTALL_DIR/ADAPTERS/claude-code.md"
log "  • Cursor:       $INSTALL_DIR/ADAPTERS/cursor.md"
log "  • Gemini CLI:   $INSTALL_DIR/ADAPTERS/gemini-cli.md"
log "  • Codex CLI:    $INSTALL_DIR/ADAPTERS/codex-cli.md"
log "  • Mistral Vibe: $INSTALL_DIR/ADAPTERS/mistral-vibe.md"
log ""
log "Onboard a project: cd <project> && (your AI tool) → /sec-init"
log "Run an audit:      /sec-audit"
log ""
