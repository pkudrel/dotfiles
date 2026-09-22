#!/usr/bin/env bash
# .NET SDK 10 for this user in ~/.dotnet (Microsoft dotnet-install.sh; apt only for native libraries)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"

DOTNET_DIR="$HOME/.dotnet"
DOTNET_CHANNEL="10.0"

sdk_version() { "$DOTNET_DIR/dotnet" --version 2>/dev/null; }

feature_status() {
  if [[ -x "$DOTNET_DIR/dotnet" ]]; then
    echo "installed SDK $(sdk_version)"
  else
    echo "not installed"
    return 1
  fi
}

# Native libraries the SDK needs. ICU and OpenSSL package names change between Ubuntu releases
# (e.g. libicu70 / libssl3 on 22.04, libicu78 / libssl3t64 on 26.04), so they are looked up.
ensure_dependencies() {
  local pkg icu ssl missing=() wanted=(ca-certificates libc6 libgcc-s1 libgssapi-krb5-2 libstdc++6 zlib1g)
  icu="$(apt_newest_matching 'libicu[0-9]+')"
  ssl="$(apt_newest_matching 'libssl3(t64)?')"
  if [[ -n "$icu" ]]; then wanted+=("$icu"); else warn "no libicu package found in apt"; fi
  if [[ -n "$ssl" ]]; then wanted+=("$ssl"); else warn "no libssl3 package found in apt"; fi
  for pkg in "${wanted[@]}"; do
    pkg_installed "$pkg" || missing+=("$pkg")
  done
  if (( ${#missing[@]} == 0 )); then
    ok "dotnet native dependencies present"
    return 0
  fi
  log "apt install: ${missing[*]}"
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

feature_install() {
  ensure_dependencies

  local installer
  installer="$(mktemp)"
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$installer" || { rm -f "$installer"; die "download failed: dotnet-install.sh"; }
  log "dotnet SDK $DOTNET_CHANNEL → $DOTNET_DIR (installs or updates to the latest $DOTNET_CHANNEL patch)"
  bash "$installer" --channel "$DOTNET_CHANNEL" --install-dir "$DOTNET_DIR" --no-path
  rm -f "$installer"

  [[ -x "$DOTNET_DIR/dotnet" ]] || die "dotnet not found in $DOTNET_DIR after install"
  ok "dotnet SDK $(sdk_version); in a new shell dotnet, DOTNET_ROOT and ~/.dotnet/tools are set up"
}

case "${1:-}" in
  status) feature_status ;;
  install) feature_install ;;
  *) die "usage: $(basename "$0") status|install" ;;
esac
