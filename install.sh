#!/usr/bin/env bash
# Universal Security Pilot — installer
# https://github.com/VikingOwl91/universal-security-pilot
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/VikingOwl91/universal-security-pilot/main/install.sh | bash
#   bash install.sh [--wire-claude] [--wire-gemini-cli] [--yes] [--uninstall]
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
ASSUME_YES=0
UNINSTALL=0

usage() {
  cat <<EOF
Universal Security Pilot — installer

Usage: install.sh [options]

Options:
  --wire-claude       Symlink slash commands into ~/.claude/commands (backs up existing files)
  --wire-gemini-cli   Symlink TOML custom commands into ~/.gemini/commands (backs up existing files)
  --yes, -y           Skip interactive prompts (assume yes)
  --uninstall         Remove the installation and any symlinks it created
  -h, --help          Show this help

Environment:
  USP_INSTALL_DIR  Override install path (default: \$HOME/.security-pilot)
  USP_REPO_URL     Override repository URL
  USP_BRANCH       Override branch (default: main)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wire-claude)     WIRE_CLAUDE=1 ;;
    --wire-gemini-cli) WIRE_GEMINI_CLI=1 ;;
    --yes|-y)          ASSUME_YES=1 ;;
    --uninstall)       UNINSTALL=1 ;;
    -h|--help)         usage; exit 0 ;;
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

if [[ "$UNINSTALL" -eq 1 ]]; then
  log "Uninstalling Universal Security Pilot..."
  remove_claude_symlinks
  remove_gemini_cli_symlinks
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

# --- Done -------------------------------------------------------------------

log ""
ok "Universal Security Pilot installed at $INSTALL_DIR"
log ""
log "${C_BLU}Next steps${C_RST}"
log "  • Claude Code:  $INSTALL_DIR/ADAPTERS/claude-code.md"
log "  • Cursor:       $INSTALL_DIR/ADAPTERS/cursor.md"
log "  • Gemini CLI:   $INSTALL_DIR/ADAPTERS/gemini-cli.md"
log ""
log "Onboard a project: cd <project> && (your AI tool) → /sec-init"
log "Run an audit:      /sec-audit"
log ""
