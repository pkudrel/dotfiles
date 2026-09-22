#!/usr/bin/env bash
# Make zsh the login shell.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

user="${USER:-$(id -un)}"
zsh_path="$(command -v zsh)" || die "zsh is not installed"
current="$(getent passwd "$user" | cut -d: -f7)"

if [[ "$current" == "$zsh_path" ]]; then
  ok "login shell is already $zsh_path"
  exit 0
fi

grep -qx "$zsh_path" /etc/shells || echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
sudo chsh -s "$zsh_path" "$user"
ok "login shell: $current → $zsh_path"
