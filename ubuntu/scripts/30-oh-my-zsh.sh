#!/usr/bin/env bash
# Oh My Zsh + Powerlevel10k theme + zsh-autosuggestions + zsh-syntax-highlighting.
# Re-running updates the git clones.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

OMZ_DIR="$HOME/.oh-my-zsh"
OMZ_CUSTOM="$OMZ_DIR/custom"

if [[ -d "$OMZ_DIR" ]]; then
  ok "Oh My Zsh present"
else
  log "installing Oh My Zsh (unattended, keeps any .zshrc, no chsh)"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

clone_or_update() {
  local repo="$1" dest="$2"
  if [[ -d "$dest/.git" ]]; then
    git -C "$dest" pull --ff-only --quiet
    ok "updated $(basename "$dest")"
  else
    mkdir -p "$(dirname "$dest")"
    git clone --depth=1 --quiet "$repo" "$dest"
    ok "cloned $(basename "$dest")"
  fi
}

clone_or_update https://github.com/romkatv/powerlevel10k.git        "$OMZ_CUSTOM/themes/powerlevel10k"
clone_or_update https://github.com/zsh-users/zsh-autosuggestions.git     "$OMZ_CUSTOM/plugins/zsh-autosuggestions"
clone_or_update https://github.com/zsh-users/zsh-syntax-highlighting.git "$OMZ_CUSTOM/plugins/zsh-syntax-highlighting"
