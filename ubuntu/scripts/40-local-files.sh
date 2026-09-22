#!/usr/bin/env bash
# Machine-local files: copied from templates/ only when missing, never overwritten.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

T="$UBUNTU_DIR/templates"

copy_if_missing "$T/zshrc.local.example"     "$HOME/.zshrc.local"
copy_if_missing "$T/gitconfig.local.example" "$HOME/.gitconfig.local"
copy_if_missing "$T/agents/config.md"        "$HOME/.agents/config.md"
copy_if_missing "$T/claude/settings.json"    "$HOME/.claude/settings.json"
mkdir -p "$HOME/.agents/issues"

# WSL: GitHub over HTTPS through Git Credential Manager from Git for Windows.
# Native Ubuntu (server): nothing to set, git uses SSH with the forwarded agent.
if is_wsl; then
  gcm="/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe"
  if [[ -e "$gcm" ]]; then
    want="${gcm// /\\ }"
    current="$(git config --file "$HOME/.gitconfig.local" --get credential.helper || true)"
    if [[ "$current" == "$want" ]]; then
      ok "credential.helper already set (Git Credential Manager)"
    else
      git config --file "$HOME/.gitconfig.local" credential.helper "$want"
      ok "credential.helper → Git Credential Manager (in ~/.gitconfig.local)"
    fi
  else
    warn "Git for Windows not found at $gcm; install it on Windows to push over HTTPS"
  fi
fi
