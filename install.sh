#!/usr/bin/env bash
# Universal Security Pilot — installer
# https://github.com/VikingOwl91/universal-security-pilot
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/VikingOwl91/universal-security-pilot/main/install.sh | bash
#   bash install.sh [--wire-claude] [--wire-gemini-cli] [--wire-cursor] [--wire-cursor-hooks] [--wire-codex-cli] [--yes] [--uninstall]
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

remove_claude_symlinks() {
  local cdir="$HOME/.claude/commands"
  local sdir="$HOME/.claude/skills"
  local name target link_dest
  if [[ -d "$cdir" ]]; then
    for name in sec-init sec-audit sec-fix ai-harden; do
      target="$cdir/${name}.md"
      [[ -L "$target" ]] || continue
      link_dest="$(readlink "$target" 2>/dev/null || true)"
      if [[ "$link_dest" == "$INSTALL_DIR/COMMANDS/${name}.md" ]]; then
        rm -f "$target" && ok "Removed symlink $target"
      fi
    done
  fi
  if [[ -d "$sdir" ]]; then
    for name in sec-audit sec-fix ai-harden; do
      target="$sdir/${name}.md"
      [[ -L "$target" ]] || continue
      link_dest="$(readlink "$target" 2>/dev/null || true)"
      if [[ "$link_dest" == "$INSTALL_DIR/SKILLS/${name}.md" ]]; then
        rm -f "$target" && ok "Removed symlink $target"
      fi
    done
  fi
}

remove_gemini_cli_symlinks() {
  local cdir="$HOME/.gemini/commands"
  local name target link_dest
  [[ -d "$cdir" ]] || return 0
  for name in sec-init sec-audit sec-fix ai-harden; do
    target="$cdir/${name}.toml"
    [[ -L "$target" ]] || continue
    link_dest="$(readlink "$target" 2>/dev/null || true)"
    if [[ "$link_dest" == "$INSTALL_DIR/ADAPTERS/gemini-cli/commands/${name}.toml" ]]; then
      rm -f "$target" && ok "Removed symlink $target"
    fi
  done
}

remove_codex_cli_symlinks() {
  local pdir="$HOME/.codex/prompts"
  local sdir="$HOME/.codex/skills"
  local name target link_dest
  if [[ -d "$pdir" ]]; then
    for name in sec-init sec-audit sec-fix ai-harden; do
      target="$pdir/${name}.md"
      [[ -L "$target" ]] || continue
      link_dest="$(readlink "$target" 2>/dev/null || true)"
      if [[ "$link_dest" == "$INSTALL_DIR/ADAPTERS/codex-cli/prompts/${name}.md" ]]; then
        rm -f "$target" && ok "Removed symlink $target"
      fi
    done
  fi
  if [[ -d "$sdir" ]]; then
    for name in sec-audit sec-fix ai-harden; do
      target="$sdir/${name}/SKILL.md"
      [[ -L "$target" ]] || continue
      link_dest="$(readlink "$target" 2>/dev/null || true)"
      if [[ "$link_dest" == "$INSTALL_DIR/ADAPTERS/codex-cli/skills/${name}/SKILL.md" ]]; then
        rm -f "$target" && ok "Removed symlink $target"
        rmdir "$sdir/${name}" 2>/dev/null || true
      fi
    done
  fi
}

remove_cursor_symlinks() {
  local cdir="$HOME/.cursor/commands"
  local hdir="$HOME/.cursor/hooks"
  local name target link_dest
  if [[ -d "$cdir" ]]; then
    for name in sec-init sec-audit sec-fix ai-harden; do
      target="$cdir/${name}.md"
      [[ -L "$target" ]] || continue
      link_dest="$(readlink "$target" 2>/dev/null || true)"
      if [[ "$link_dest" == "$INSTALL_DIR/COMMANDS/${name}.md" ]]; then
        rm -f "$target" && ok "Removed symlink $target"
      fi
    done
  fi
  if [[ -d "$hdir" ]]; then
    for name in usp-audit usp-redact-secrets usp-block-dangerous-shell usp-mcp-dial-control; do
      target="$hdir/${name}.sh"
      [[ -L "$target" ]] || continue
      link_dest="$(readlink "$target" 2>/dev/null || true)"
      if [[ "$link_dest" == "$INSTALL_DIR/ADAPTERS/cursor/hooks/${name}.sh" ]]; then
        rm -f "$target" && ok "Removed symlink $target"
      fi
    done
  fi
  # ~/.cursor/hooks.json is intentionally left in place — it's a real file
  # the user may have customized after USP wrote it. They can remove it manually.
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
  remove_cursor_symlinks
  strip_stanza "$HOME/.claude/CLAUDE.md"
  strip_stanza "$HOME/.gemini/GEMINI.md"
  strip_stanza "$HOME/.codex/AGENTS.md"
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

if [[ -e "$INSTALL_DIR" ]]; then
  [[ -d "$INSTALL_DIR/.git" ]] || die "$INSTALL_DIR exists but is not a git checkout. Move/remove it and re-run."

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
  "ADAPTERS/claude-code/stanza.md"
  "ADAPTERS/cursor/stanza.md"
  "ADAPTERS/gemini-cli/stanza.md"
  "ADAPTERS/codex-cli/stanza.md"
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

if [[ "$WIRE_CLAUDE" -eq 1 ]]; then
  wire_claude
elif [[ -d "$HOME/.claude" ]]; then
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    wire_claude
  elif [[ -t 0 && -t 1 ]]; then
    read -r -p "Detected ~/.claude — wire slash commands into Claude Code? [y/N] " ans
    case "$ans" in
      [yY]|[yY][eE][sS]) wire_claude ;;
      *) log "(skipped — re-run with --wire-claude to enable later)" ;;
    esac
  else
    log ""
    log "Detected ~/.claude. To wire Claude Code slash commands, re-run with:"
    log "  bash $INSTALL_DIR/install.sh --wire-claude"
  fi
fi

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

if [[ "$WIRE_GEMINI_CLI" -eq 1 ]]; then
  wire_gemini_cli
elif [[ -d "$HOME/.gemini" ]]; then
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    wire_gemini_cli
  elif [[ -t 0 && -t 1 ]]; then
    read -r -p "Detected ~/.gemini — wire TOML custom commands into Gemini CLI? [y/N] " ans
    case "$ans" in
      [yY]|[yY][eE][sS]) wire_gemini_cli ;;
      *) log "(skipped — re-run with --wire-gemini-cli to enable later)" ;;
    esac
  else
    log ""
    log "Detected ~/.gemini. To wire Gemini CLI custom commands, re-run with:"
    log "  bash $INSTALL_DIR/install.sh --wire-gemini-cli"
  fi
fi

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

if [[ "$WIRE_CURSOR" -eq 1 ]]; then
  wire_cursor
elif [[ -d "$HOME/.cursor" ]]; then
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    wire_cursor
  elif [[ -t 0 && -t 1 ]]; then
    read -r -p "Detected ~/.cursor — wire slash commands into Cursor? [y/N] " ans
    case "$ans" in
      [yY]|[yY][eE][sS]) wire_cursor ;;
      *) log "(skipped — re-run with --wire-cursor to enable later)" ;;
    esac
  else
    log ""
    log "Detected ~/.cursor. To wire Cursor slash commands, re-run with:"
    log "  bash $INSTALL_DIR/install.sh --wire-cursor"
  fi
fi

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

if [[ "$WIRE_CODEX_CLI" -eq 1 ]]; then
  wire_codex_cli
elif [[ -d "$HOME/.codex" ]]; then
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    wire_codex_cli
  elif [[ -t 0 && -t 1 ]]; then
    read -r -p "Detected ~/.codex — wire custom prompts and skills into Codex CLI? [y/N] " ans
    case "$ans" in
      [yY]|[yY][eE][sS]) wire_codex_cli ;;
      *) log "(skipped — re-run with --wire-codex-cli to enable later)" ;;
    esac
  else
    log ""
    log "Detected ~/.codex. To wire Codex CLI prompts and skills, re-run with:"
    log "  bash $INSTALL_DIR/install.sh --wire-codex-cli"
  fi
fi

# --- Detection summary + suggested next steps -------------------------------

print_status_line() {
  # print_status_line <label> <bin?> <dir?> <wired?> <wire-hint>
  local label="$1" bin="$2" dir="$3" wired="$4" hint="$5"
  if [[ $bin -eq 1 && $dir -eq 1 ]]; then
    if [[ $wired -eq 1 ]]; then
      printf '  %s✓%s %-22s — %swired%s\n' "$C_GRN" "$C_RST" "$label" "$C_GRN" "$C_RST"
    else
      printf '  %s✓%s %-22s — not wired (%s)\n' "$C_GRN" "$C_RST" "$label" "$hint"
    fi
  elif [[ $bin -eq 1 ]]; then
    printf '  %s!%s %-22s — binary present, config dir missing (run the CLI once to initialize)\n' "$C_YLW" "$C_RST" "$label"
  elif [[ $dir -eq 1 ]]; then
    printf '  %s!%s %-22s — config dir present, binary not in PATH\n' "$C_YLW" "$C_RST" "$label"
  else
    printf '  − %-22s — not detected\n' "$label"
  fi
}

# Per-tool state
claude_bin=0; cursor_bin=0; gemini_bin=0; codex_bin=0
claude_dir=0; cursor_dir=0; gemini_dir=0; codex_dir=0
claude_wired=0; cursor_cmds_wired=0; cursor_hooks_wired=0; gemini_wired=0; codex_wired=0

command -v claude >/dev/null 2>&1 && claude_bin=1
command -v cursor >/dev/null 2>&1 && cursor_bin=1
command -v gemini >/dev/null 2>&1 && gemini_bin=1
command -v codex  >/dev/null 2>&1 && codex_bin=1

[[ -d "$HOME/.claude" ]] && claude_dir=1
[[ -d "$HOME/.cursor" ]] && cursor_dir=1
[[ -d "$HOME/.gemini" ]] && gemini_dir=1
[[ -d "$HOME/.codex"  ]] && codex_dir=1

[[ -L "$HOME/.claude/commands/sec-init.md"   ]] && claude_wired=1
[[ -L "$HOME/.cursor/commands/sec-init.md"   ]] && cursor_cmds_wired=1
[[ -L "$HOME/.cursor/hooks/usp-audit.sh"     ]] && cursor_hooks_wired=1
[[ -L "$HOME/.gemini/commands/sec-init.toml" ]] && gemini_wired=1
[[ -L "$HOME/.codex/prompts/sec-init.md"     ]] && codex_wired=1

log ""
log "${C_BLU}Detected tools${C_RST}"
print_status_line "Claude Code"          "$claude_bin" "$claude_dir" "$claude_wired"      "run --wire-claude"
if [[ $cursor_bin -eq 1 && $cursor_dir -eq 1 ]]; then
  # Cursor has two independent wires; describe each.
  if [[ $cursor_cmds_wired -eq 1 ]]; then
    if [[ $cursor_hooks_wired -eq 1 ]]; then
      printf '  %s✓%s %-22s — %swired%s (commands + hooks)\n' "$C_GRN" "$C_RST" "Cursor" "$C_GRN" "$C_RST"
    else
      printf '  %s✓%s %-22s — commands %swired%s, hooks not wired (--wire-cursor-hooks for policy enforcement)\n' "$C_GRN" "$C_RST" "Cursor" "$C_GRN" "$C_RST"
    fi
  else
    printf '  %s✓%s %-22s — not wired (run --wire-cursor)\n' "$C_GRN" "$C_RST" "Cursor"
  fi
else
  print_status_line "Cursor" "$cursor_bin" "$cursor_dir" 0 "run --wire-cursor"
fi
print_status_line "Gemini CLI"           "$gemini_bin" "$gemini_dir" "$gemini_wired"      "run --wire-gemini-cli"
print_status_line "Codex CLI"            "$codex_bin"  "$codex_dir"  "$codex_wired"       "run --wire-codex-cli"

has_suggestions=0
[[ $claude_bin -eq 1 && $claude_dir -eq 1 && $claude_wired       -eq 0 ]] && has_suggestions=1
[[ $cursor_bin -eq 1 && $cursor_dir -eq 1 && $cursor_cmds_wired  -eq 0 ]] && has_suggestions=1
[[ $cursor_bin -eq 1 && $cursor_dir -eq 1 && $cursor_hooks_wired -eq 0 ]] && has_suggestions=1
[[ $gemini_bin -eq 1 && $gemini_dir -eq 1 && $gemini_wired       -eq 0 ]] && has_suggestions=1
[[ $codex_bin  -eq 1 && $codex_dir  -eq 1 && $codex_wired        -eq 0 ]] && has_suggestions=1

if [[ $has_suggestions -eq 1 ]]; then
  log ""
  log "${C_BLU}Suggested next steps${C_RST}"
  [[ $claude_bin -eq 1 && $claude_dir -eq 1 && $claude_wired      -eq 0 ]] && \
    log "  bash $INSTALL_DIR/install.sh --wire-claude"
  [[ $cursor_bin -eq 1 && $cursor_dir -eq 1 && $cursor_cmds_wired -eq 0 ]] && \
    log "  bash $INSTALL_DIR/install.sh --wire-cursor             # slash commands"
  [[ $cursor_bin -eq 1 && $cursor_dir -eq 1 && $cursor_hooks_wired -eq 0 ]] && \
    log "  bash $INSTALL_DIR/install.sh --wire-cursor-hooks       # opt-in: policy enforcement (jq required)"
  [[ $gemini_bin -eq 1 && $gemini_dir -eq 1 && $gemini_wired      -eq 0 ]] && \
    log "  bash $INSTALL_DIR/install.sh --wire-gemini-cli"
  [[ $codex_bin  -eq 1 && $codex_dir  -eq 1 && $codex_wired       -eq 0 ]] && \
    log "  bash $INSTALL_DIR/install.sh --wire-codex-cli"
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
log ""
log "Onboard a project: cd <project> && (your AI tool) → /sec-init"
log "Run an audit:      /sec-audit"
log ""
