#!/usr/bin/env bash
# Tailscale client (official install script); log in once with: sudo tailscale up
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"

feature_status() {
  if ! has_systemd; then
    echo "needs systemd"
    return 2
  fi
  if command_exists tailscale; then
    echo "installed $(tailscale version 2>/dev/null | head -n1)"
  else
    echo "not installed"
    return 1
  fi
}

feature_install() {
  has_systemd || die "systemd is not running (WSL: [boot] systemd=true in /etc/wsl.conf, then wsl --shutdown)"

  # The script adds Tailscale's apt repository for this Ubuntu release and installs or updates the package.
  log "tailscale: official install script"
  curl -fsSL https://tailscale.com/install.sh | sh
  hash -r
  command_exists tailscale || die "tailscale not found after install"
  sudo systemctl enable --now tailscaled

  if is_wsl; then
    warn "WSL: this distro is its own device in your tailnet, next to the Windows client"
  fi
  if tailscale status >/dev/null 2>&1; then
    ok "tailscale $(tailscale version | head -n1), logged in"
  else
    ok "tailscale $(tailscale version | head -n1)"
    warn "log in once: sudo tailscale up"
  fi
}

case "${1:-}" in
  status) feature_status ;;
  install) feature_install ;;
  *) die "usage: $(basename "$0") status|install" ;;
esac
