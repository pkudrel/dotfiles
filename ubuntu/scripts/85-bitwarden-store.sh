#!/usr/bin/env bash
# Files from the Bitwarden secure note "bitwarden-store" (e.g. the git identity), as its attachment _manifest.txt
# says (code: store-lib.sh). One master password prompt (Enter skips); changed files are overwritten.
# Change the store itself with ubuntu/store.sh (dlab-store-*).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/store-lib.sh"

if ! bw_open_session; then
  warn "Bitwarden skipped, $STORE_ITEM_NAME not applied (later: install.sh bitwarden-store or dlab-store-restore)"
  check_git_identity
  exit 0
fi
store_start_temp
trap store_stop EXIT

if store_load_item; then
  store_restore
else
  warn "Bitwarden has no item '$STORE_ITEM_NAME' (a secure note with the files and $STORE_MANIFEST attached); nothing done"
fi
check_git_identity
