#!/usr/bin/env bash
# Changes the Bitwarden secure note "Bitwarden-store" (the private files that install step bitwarden-store restores).
#
#   store.sh list              attachments, the manifest lines that use them, and what does not match
#   store.sh add <file>        new attachment + its manifest line (the manifest opens in the editor)
#   store.sh replace <file>    new version of an attachment (the attachment name is the file name)
#   store.sh remove <name>     removes an attachment and its manifest lines (asks first)
#   store.sh manifest-edit     edit _manifest.txt (checked before it is saved)
#
# One master password prompt per command (Enter cancels). A replaced or removed attachment is kept as
# "<name>.prev" (one step back). After add, replace, remove and manifest-edit this machine is updated
# (the bitwarden-store step), in the same session. Editor: $EDITOR, else nano.
# dlab commands: dlab-store-list, -add, -replace, -remove, -manifest-edit. Same as windows/store.ps1.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/scripts/store-lib.sh"

usage="usage: store.sh list | add <file> | replace <file> | remove <name> | manifest-edit"
command="${1:-}" target="${2:-}"
case "$command" in
  list | manifest-edit) ;;
  add | replace | remove) [[ -n "$target" ]] || die "$usage" ;;
  *) die "$usage" ;;
esac

# add / replace: the local file, checked before the password prompt.
file="" name=""
if [[ "$command" == add || "$command" == replace ]]; then
  [[ -f "$target" ]] || die "file not found: $target"
  file="$(realpath "$target")"
  name="$(basename "$file")"
  if [[ "$name" == "$STORE_MANIFEST" || "$name" == *.prev ]]; then
    die "$name is reserved ($STORE_MANIFEST: dlab-store-manifest-edit; *.prev: previous versions)"
  fi
fi


######
###### COMMANDS
######

cmd_list() {
  local manifest="" rc=0 i attachment size note uses
  store_get "$STORE_MANIFEST" || rc=$?
  if ((rc == 0)); then manifest="$REPLY"; manifest_parse "$manifest"; else M_ATT=() M_PROBLEMS=(); fi

  log "$STORE_ITEM_NAME: $(jq '.attachments // [] | length' <<<"$STORE_ITEM_JSON") attachment(s)"
  while IFS=$'\t' read -r attachment size; do
    uses=""
    for i in "${!M_ATT[@]}"; do
      [[ "${M_ATT[i]}" == "$attachment" ]] || continue
      # shellcheck disable=SC2153  # M_ACT is set by manifest_parse (store-lib.sh)
      uses+="${uses:+; }${M_SYS[i]} ${M_ACT[i]}${M_PAR[i]:+ ${M_PAR[i]}}${M_HOSTS[i]:+ host=${M_HOSTS[i]}}"
      [[ "${M_WHEN[i]}" == always ]] || uses+=" when=${M_WHEN[i]}"
      [[ -z "${M_MODE[i]}" ]] || uses+=" mode=${M_MODE[i]}"
    done
    if [[ "$attachment" == "$STORE_MANIFEST" ]]; then note="(manifest)"
    elif [[ "$attachment" == *.prev ]]; then note="(previous version)"
    elif [[ -n "${STORE_ATT_DUP[$attachment]:-}" ]]; then note="(DUPLICATE NAME: remove the extra one in Bitwarden)"
    elif [[ -z "$uses" ]]; then note="(not used by the manifest)"
    else note="$uses"
    fi
    printf '  %-28s %10s  %s\n' "$attachment" "$size" "$note"
  done < <(jq -r '(.attachments // []) | sort_by(.fileName)[] | [.fileName, (.sizeName // ((.size // "?") + " B"))] | @tsv' <<<"$STORE_ITEM_JSON")

  [[ -n "$manifest" ]] || warn "no $STORE_MANIFEST yet: dlab-store-manifest-edit"
  for i in "${!M_ATT[@]}"; do
    if ! store_is_attachment "${M_ATT[i]}" && [[ -z "${STORE_ATT_DUP[${M_ATT[i]}]:-}" ]]; then
      warn "manifest line ${M_NUM[i]} uses a missing attachment: ${M_ATT[i]}"
    fi
  done
  for i in "${M_PROBLEMS[@]}"; do warn "manifest: $i"; done
  CHANGED=0
}

# The manifest to edit → REPLY: a copy of the current one, or the template when there is none.
manifest_draft() {
  local rc=0 draft
  store_tmpdir
  draft="$REPLY/$STORE_MANIFEST"
  store_get "$STORE_MANIFEST" || rc=$?
  case $rc in
    0) cp "$REPLY" "$draft" ;;
    1) printf '%s\n' "$STORE_TEMPLATE" >"$draft" ;;
    *) die "cannot read $STORE_MANIFEST (duplicate or download failed)" ;;
  esac
  REPLY="$draft"
}

# Saves an edited manifest (the old one stays as _manifest.txt.prev); CHANGED=1 when it changed.
manifest_save() {
  store_set "$STORE_MANIFEST" "$1"
  if ((STORE_CHANGED)); then ok "$STORE_MANIFEST saved"; CHANGED=1; else ok "$STORE_MANIFEST unchanged"; fi
}

cmd_add() {
  local draft i used=0
  store_assert_name "$name"
  ! store_is_attachment "$name" || die "$STORE_ITEM_NAME already has $name: dlab-store-replace $target"
  manifest_draft
  draft="$REPLY"
  printf '%s | %s | copy | \n' "$name" "$STORE_SYSTEM" >>"$draft"
  log "complete the line for $name in $STORE_MANIFEST (action params: the target path), save and close the editor"
  manifest_edit "$draft" || { warn "cancelled, nothing saved"; CHANGED=0; return 0; }
  for i in "${!M_ATT[@]}"; do [[ "${M_ATT[i]}" != "$name" ]] || used=1; done
  ((used)) || warn "no manifest line uses $name: it is stored but not restored anywhere"
  store_upload "$file" "$name" || die "upload of $name failed; nothing saved"
  ok "$name added to $STORE_ITEM_NAME"
  manifest_save "$draft"
  CHANGED=1
}

cmd_replace() {
  store_assert_name "$name"
  if ! store_is_attachment "$name"; then
    store_is_attachment "$name.prev" || die "$STORE_ITEM_NAME has no attachment $name (new file: dlab-store-add $target)"
    # An earlier replace stopped after the delete: only the upload is missing.
    store_upload "$file" "$name" || die "upload of $name failed; the previous version is $name.prev"
    ok "$name uploaded (the earlier replace had stopped; previous version: $name.prev)"
    CHANGED=1
    return 0
  fi
  store_set "$name" "$file"
  if ((STORE_CHANGED)); then ok "$name replaced (previous version: $name.prev)"; CHANGED=1; else ok "$name unchanged (same content)"; CHANGED=0; fi
}

cmd_remove() {
  local manifest="" lines="" answer draft rc=0 shown
  name="$target"
  [[ "$name" != "$STORE_MANIFEST" ]] || die "$STORE_MANIFEST cannot be removed (edit it: dlab-store-manifest-edit)"
  store_assert_name "$name"
  store_is_attachment "$name" || die "$STORE_ITEM_NAME has no attachment $name (see dlab-store-list)"
  store_get "$STORE_MANIFEST" || rc=$?
  if ((rc == 0)); then manifest="$REPLY"; lines="$(manifest_lines_for "$manifest" "$name")"; fi
  log "remove $name from $STORE_ITEM_NAME (kept as $name.prev)"
  if [[ -n "$lines" ]]; then
    echo '  and these manifest lines:'
    mapfile -t shown <<<"$lines"
    printf '    %s\n' "${shown[@]}"
  fi
  read -rp 'Continue? (y/N) ' answer
  if [[ "${answer,,}" != y && "${answer,,}" != yes ]]; then warn "cancelled, nothing changed"; CHANGED=0; return 0; fi

  store_set "$name" ""
  ok "$name removed (previous version: $name.prev)"
  if [[ -n "$lines" ]]; then
    store_tmpdir
    draft="$REPLY/$STORE_MANIFEST"
    grep -vxF -f <(printf '%s\n' "$lines") "$manifest" >"$draft" || true
    manifest_save "$draft"
  fi
  CHANGED=1
}

cmd_manifest_edit() {
  manifest_draft
  local draft="$REPLY"
  manifest_edit "$draft" || { warn "cancelled, nothing saved"; CHANGED=0; return 0; }
  CHANGED=0
  manifest_save "$draft"
}


######
###### RUN
######

if ! bw_open_session; then
  warn "cancelled (no master password)"
  exit 0
fi
store_start_temp
trap store_stop EXIT

if ! store_load_item; then
  if [[ "$command" != add && "$command" != manifest-edit ]] || ! store_create_item; then
    warn "Bitwarden has no item '$STORE_ITEM_NAME'; nothing done"
    exit 0
  fi
fi

CHANGED=0
case "$command" in
  list) cmd_list ;;
  add) cmd_add ;;
  replace) cmd_replace ;;
  remove) cmd_remove ;;
  manifest-edit) cmd_manifest_edit ;;
esac
if ((CHANGED)); then
  log "updating this machine (bitwarden-store)"
  store_restore
fi
