#!/usr/bin/env bash
# usp-block-dangerous-shell.sh — beforeShellExecution hook.
# Denies catastrophic patterns outright; asks before credential-touching
# or history-rewriting commands.
#
# Decision matrix:
#   deny   — irreversible mass deletion, remote-code-piped-to-shell,
#            world-writable chmod, fork bombs.
#   ask    — git history rewrite, cloud auth rotation, files under
#            ~/.aws / ~/.ssh / ~/.kube.
#   allow  — everything else.
#
# Requires: jq.

input="$(cat)"
command="$(printf '%s' "$input" | jq -r '.command // empty' 2>/dev/null || true)"

deny() {
  cat <<__DENY__
{"continue":true,"permission":"deny","userMessage":"USP blocked dangerous shell: $1","agentMessage":"The command was blocked by Universal Security Pilot. Reason: $1. Use a safer alternative or split the operation; do not retry the same command."}
__DENY__
  exit 0
}

ask() {
  cat <<__ASK__
{"continue":true,"permission":"ask","userMessage":"USP: review before approving — $1","agentMessage":"Universal Security Pilot flagged this command for review: $1."}
__ASK__
  exit 0
}

allow() {
  cat <<'__ALLOW__'
{"continue":true,"permission":"allow"}
__ALLOW__
  exit 0
}

# --- Catastrophic patterns: deny ------------------------------------------
# `rm -rf /` and friends — must require an explicit terminator after the
# target so we don't false-positive on `rm -rf /tmp/foo`.
# shellcheck disable=SC2016  # literal '$HOME' / '${HOME}' match is intentional
case "$command" in
  *"rm -rf /"|*"rm -rf / "*|*"rm -rf /;"*|*"rm -rf /&"*|*"rm -rf /|"*)
    deny "rm -rf / (root) — irreversible mass deletion" ;;
  *"rm -rf /*"*)
    deny "rm -rf /* — root-glob mass deletion" ;;
  *"rm -rf ~"|*"rm -rf ~ "*|*"rm -rf ~;"*|*"rm -rf ~/"|*"rm -rf ~/*"*)
    deny "rm -rf ~ (home) — irreversible mass deletion" ;;
  *'rm -rf $HOME'*|*'rm -rf "$HOME"'*|*'rm -rf ${HOME}'*)
    deny "rm -rf \$HOME — irreversible mass deletion" ;;
esac
case "$command" in
  *"curl"*"| sh"*|*"curl"*"|sh"*|*"curl"*"| bash"*|*"curl"*"|bash"*)
    deny "curl piped to a shell — runs unverified remote code" ;;
  *"wget"*"| sh"*|*"wget"*"|sh"*|*"wget"*"| bash"*|*"wget"*"|bash"*)
    deny "wget piped to a shell — runs unverified remote code" ;;
  *"chmod 777"*|*"chmod -R 777"*|*"chmod -R 0777"*)
    deny "chmod 777 — world-writable permissions" ;;
  *":(){ :|:& };:"*|*":(){:|:&};:"*)
    deny "fork bomb pattern detected" ;;
  *"dd "*"of=/dev/sd"*|*"dd "*"of=/dev/nvme"*|*"dd "*"of=/dev/hd"*)
    deny "dd writing to a raw block device — irreversible data destruction" ;;
esac

# --- History-rewrite / shared-state: ask ----------------------------------
case "$command" in
  *"git filter-branch"*|*"git filter-repo"*)
    ask "git history rewrite — affects all collaborators" ;;
  *"git push"*"--force"*|*"git push -f"*)
    ask "force push — can overwrite upstream history" ;;
  *"git reset --hard"*)
    ask "git reset --hard — discards local changes" ;;
esac

# --- Credential-touching: ask ---------------------------------------------
case "$command" in
  *"aws "*"configure"*|*"gcloud auth"*|*"kubectl config "*|*"docker login"*|*"helm registry login"*)
    ask "credential / auth command — verify scope and target account" ;;
  *".aws/credentials"*|*".kube/config"*|*".ssh/id_"*|*"id_rsa"*|*"id_ed25519"*|*"id_ecdsa"*)
    ask "command touches a credential file — verify intent" ;;
esac

allow
