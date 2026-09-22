#!/usr/bin/env bash
# Optional features: install/update the ones remembered on this machine (pick them with features.sh).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

bash "$UBUNTU_DIR/features.sh" --update
