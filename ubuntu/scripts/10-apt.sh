#!/usr/bin/env bash
# Install the apt packages listed in packages/apt.txt (installed ones are skipped).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

mapfile -t packages < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$UBUNTU_DIR/packages/apt.txt" | grep -v '^$')

missing=()
for pkg in "${packages[@]}"; do
  dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed' || missing+=("$pkg")
done

if (( ${#missing[@]} == 0 )); then
  ok "all apt packages already installed"
  exit 0
fi

log "apt install: ${missing[*]}"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
ok "apt packages installed"
