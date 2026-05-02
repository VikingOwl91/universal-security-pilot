#!/usr/bin/env bash
# usp-audit.sh — append every hook payload to a Universal Security Pilot
# audit trail. Wired to beforeShellExecution, beforeMCPExecution,
# beforeSubmitPrompt, and stop. Always returns allow — observability only.
#
# Log resolution (in order):
#   1. <project_root>/.security-pilot/audit-trail.log when in-tree.
#   2. ~/.security-pilot/audit-trail.log otherwise.

input="$(cat)"

{
  timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown)"
  project_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"

  if [[ -n "$project_root" && -d "$project_root/.security-pilot" ]]; then
    log_file="$project_root/.security-pilot/audit-trail.log"
  else
    log_file="$HOME/.security-pilot/audit-trail.log"
    mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
  fi

  printf '[%s] %s\n' "$timestamp" "$input" >> "$log_file" 2>/dev/null || true
} >/dev/null 2>&1

cat <<'__ALLOW__'
{"continue":true,"permission":"allow"}
__ALLOW__
