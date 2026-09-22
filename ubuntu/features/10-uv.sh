#!/usr/bin/env bash
# Python projects, packages and Python versions (uv, official installer into ~/.local/bin)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"

uv_version() { uv --version 2>/dev/null | awk '{print $2}'; }

feature_status() {
  if command_exists uv; then
    echo "installed $(uv_version)"
  else
    echo "not installed"
    return 1
  fi
}

feature_install() {
  if command_exists uv; then
    log "uv $(uv_version) present, updating"
    uv self update || warn "uv self update failed (was uv installed another way?)"
  else
    log "installing uv (no changes to shell files)"
    curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
    hash -r
    command_exists uv || die "uv not found on PATH after install (expected in $LOCAL_BIN)"
  fi
  ok "uv $(uv_version); Python versions: uv python install / uv python list"
}

case "${1:-}" in
  status) feature_status ;;
  install) feature_install ;;
  *) die "usage: $(basename "$0") status|install" ;;
esac
