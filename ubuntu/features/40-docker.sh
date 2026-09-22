#!/usr/bin/env bash
# Docker Engine with buildx and compose (Docker's apt repository; you join the docker group)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"

DOCKER_REPO="https://download.docker.com/linux/ubuntu"
DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
# Packages Docker's documentation says to remove first; they conflict with docker-ce.
CONFLICTING_PACKAGES=(docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc)

docker_version() { docker --version 2>/dev/null | awk '{print $3}' | tr -d ,; }

feature_status() {
  if ! has_systemd; then
    echo "needs systemd"
    return 2
  fi
  if pkg_installed docker-ce; then
    echo "installed $(docker_version)"
  else
    echo "not installed"
    return 1
  fi
}

feature_install() {
  has_systemd || die "systemd is not running (WSL: [boot] systemd=true in /etc/wsl.conf, then wsl --shutdown)"

  local docker_bin
  docker_bin="$(command -v docker || true)"
  if is_wsl && [[ -n "$docker_bin" && "$(readlink -f "$docker_bin")" == /mnt/wsl/* ]]; then
    warn "Docker Desktop's WSL integration is on for this distro; its docker CLI shadows Docker Engine."
    warn "Turn it off: Docker Desktop → Settings → Resources → WSL integration."
  fi

  local pkg found=()
  for pkg in "${CONFLICTING_PACKAGES[@]}"; do
    if pkg_installed "$pkg"; then found+=("$pkg"); fi
  done
  (( ${#found[@]} == 0 )) || die "remove conflicting packages first: sudo apt-get remove ${found[*]}"

  local codename arch
  codename="$(os_codename)"
  arch="$(dpkg --print-architecture)"
  curl -fsSI -o /dev/null "$DOCKER_REPO/dists/$codename/Release" \
    || die "Docker has no apt repository for Ubuntu '$codename' yet"

  if grep -rqsF --exclude=docker.list "$DOCKER_REPO" /etc/apt/sources.list.d; then
    ok "Docker apt repository already configured in another file, left as is"
  else
    log "Docker apt repository for $codename"
    sudo install -d -m 0755 /etc/apt/keyrings
    curl -fsSL "$DOCKER_REPO/gpg" | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] $DOCKER_REPO $codename stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  fi

  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${DOCKER_PACKAGES[@]}"
  sudo systemctl enable --now docker

  local user
  user="$(id -un)"
  if id -nG "$user" | tr ' ' '\n' | grep -qx docker; then
    ok "$user is in the docker group"
  else
    sudo usermod -aG docker "$user"
    warn "added $user to the docker group (effectively root access)"
    if is_wsl; then
      warn "log out and back in: close all terminals of this distro, or run 'wsl --terminate $WSL_DISTRO_NAME' in Windows"
    else
      warn "log out and back in (reconnect SSH) before using docker without sudo"
    fi
  fi
  ok "docker $(docker_version); test: docker run hello-world"
}

case "${1:-}" in
  status) feature_status ;;
  install) feature_install ;;
  *) die "usage: $(basename "$0") status|install" ;;
esac
