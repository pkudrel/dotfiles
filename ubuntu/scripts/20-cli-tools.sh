#!/usr/bin/env bash
# fzf, eza, zoxide: use apt when it has a good enough version, otherwise the
# official GitHub release binary in ~/.local/bin. No distro versions hard-coded.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FZF_MIN="0.48.0" # first version with `fzf --zsh`

fzf_version() { fzf --version 2>/dev/null | awk '{print $1}'; }

ensure_fzf() {
  if command_exists fzf && version_ge "$(fzf_version)" "$FZF_MIN"; then
    ok "fzf $(fzf_version)"
    return
  fi
  local cand tag
  cand="$(apt_candidate fzf)"
  if [[ -n "$cand" ]] && version_ge "$cand" "$FZF_MIN"; then
    log "fzf: apt ($cand)"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y fzf
  else
    tag="$(github_latest_tag junegunn/fzf)"
    log "fzf: apt has '${cand:-none}' (< $FZF_MIN), using GitHub release $tag"
    install_from_tarball "https://github.com/junegunn/fzf/releases/download/${tag}/fzf-${tag#v}-linux_$(dpkg --print-architecture).tar.gz" fzf
  fi
  hash -r
  ok "fzf $(fzf_version)"
}

ensure_eza() {
  if command_exists eza; then
    ok "eza present"
    return
  fi
  if [[ -n "$(apt_candidate eza)" ]]; then
    log "eza: apt"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y eza
  else
    log "eza: not in apt, using GitHub release"
    install_from_tarball "https://github.com/eza-community/eza/releases/latest/download/eza_$(uname -m)-unknown-linux-gnu.tar.gz" eza
  fi
}

ensure_zoxide() {
  if command_exists zoxide; then
    ok "zoxide present"
    return
  fi
  local tag
  if [[ -n "$(apt_candidate zoxide)" ]]; then
    log "zoxide: apt"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y zoxide
  else
    tag="$(github_latest_tag ajeetdsouza/zoxide)"
    log "zoxide: not in apt, using GitHub release $tag"
    install_from_tarball "https://github.com/ajeetdsouza/zoxide/releases/download/${tag}/zoxide-${tag#v}-$(uname -m)-unknown-linux-musl.tar.gz" zoxide
  fi
}

ensure_fzf
ensure_eza
ensure_zoxide
