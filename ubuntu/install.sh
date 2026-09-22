#!/usr/bin/env bash
# Set up (or refresh) an Ubuntu machine, WSL or native, from this repo. Safe to re-run.
#
#   ~/.dotfiles/ubuntu/install.sh             # all steps
#   ~/.dotfiles/ubuntu/install.sh stow zsh    # only steps whose name contains "stow" or "zsh"
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/scripts" && pwd -P)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
export BACKUP_DIR
source "$SCRIPTS_DIR/lib.sh"

[[ $EUID -ne 0 ]] || die "run as your normal user, not root (sudo is used where needed)"
command_exists sudo || die "sudo is required"

mapfile -t steps < <(find "$SCRIPTS_DIR" -maxdepth 1 -name '[0-9][0-9]-*.sh' | sort)

if (( $# > 0 )); then
  selected=()
  for step in "${steps[@]}"; do
    for filter in "$@"; do
      if [[ "$(basename "$step")" == *"$filter"* ]]; then
        selected+=("$step")
        break
      fi
    done
  done
  (( ${#selected[@]} > 0 )) || die "no step matches: $*"
  steps=("${selected[@]}")
fi

log "environment: $(is_wsl && echo WSL || echo native) / $(. /etc/os-release && echo "$PRETTY_NAME")"
sudo -v

for step in "${steps[@]}"; do
  log "step $(basename "$step")"
  bash "$step"
done

echo
ok "done"
[[ -d "$BACKUP_DIR" ]] && warn "replaced files were moved to $BACKUP_DIR"

cat <<'EOF'

Next steps:
  - start a new shell:  exec zsh   (or open a new terminal / reconnect)
  - optional tools (uv, node, dotnet, docker, tailscale, claude-code): ~/.dotfiles/ubuntu/features.sh
    Claude Code is one of them: ~/.dotfiles/ubuntu/features.sh claude-code   (then run 'claude' once to log in)
EOF
if is_wsl; then
  cat <<'EOF'
  - Nerd Font (Windows, once per computer): MesloLGS NF with
      powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ~/.dotfiles/windows/fonts/install-nerd-font.ps1)"
    Consolas NF (the Windows Terminal default) comes from Bitwarden: windows\install.ps1 bitwarden-store
    Windows Terminal → Settings → Defaults → Appearance → Font face: Consolas NF (or MesloLGS NF)
EOF
fi
