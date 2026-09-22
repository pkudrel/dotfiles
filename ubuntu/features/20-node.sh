#!/usr/bin/env bash
# Node.js through fnm: latest LTS as default, version follows .nvmrc / .node-version on cd
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"

fnm_version() { fnm --version 2>/dev/null | awk '{print $2}'; }

feature_status() {
  if command_exists fnm; then
    echo "installed fnm $(fnm_version)"
  else
    echo "not installed"
    return 1
  fi
}

feature_install() {
  log "fnm: official installer into $LOCAL_BIN (installs or updates, no changes to shell files)"
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$LOCAL_BIN" --skip-shell
  hash -r
  command_exists fnm || die "fnm not found in $LOCAL_BIN after install"
  eval "$(fnm env --shell bash)"

  local lts
  lts="$(fnm ls-remote --lts --latest | awk 'NR == 1 {print $1}')"
  [[ "$lts" == v* ]] || die "could not find the latest Node.js LTS version"
  if fnm list | grep -qw -- "$lts"; then
    ok "node $lts already installed"
  else
    log "node $lts (latest LTS)"
    fnm install "$lts"
  fi
  fnm default "$lts"
  ok "fnm $(fnm_version), default node $lts; older versions stay installed (fnm list / fnm uninstall)"
}

case "${1:-}" in
  status) feature_status ;;
  install) feature_install ;;
  *) die "usage: $(basename "$0") status|install" ;;
esac
