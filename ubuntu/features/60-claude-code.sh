#!/usr/bin/env bash
# Claude Code CLI (official native installer; it keeps itself updated afterwards)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"

# "2.1.273 (Claude Code)" -> "2.1.273"
claude_version() { claude --version 2>/dev/null | awk '{print $1}'; }

feature_status() {
  if command_exists claude; then
    echo "installed $(claude_version)"
  else
    echo "not installed"
    return 1
  fi
}

feature_install() {
  if command_exists claude; then
    log "Claude Code $(claude_version) present, updating"
    claude update || warn "claude update failed (was Claude Code installed another way?)"
  else
    log "installing Claude Code"
    curl -fsSL https://claude.ai/install.sh | bash
    hash -r
    command_exists claude || die "claude not found on PATH after install (expected in $LOCAL_BIN)"
  fi
  ok "Claude Code $(claude_version); run 'claude' once to log in"
}

case "${1:-}" in
  status) feature_status ;;
  install) feature_install ;;
  *) die "usage: $(basename "$0") status|install" ;;
esac
