#!/usr/bin/env bash
# Bitwarden-store: shared code of the restore step (scripts/85-bitwarden-store.sh) and the store commands (store.sh).
# The secure note "Bitwarden-store" holds the files as attachments; its attachment _manifest.txt says what to do with
# each (actions: copy, font, unzip). The repo knows only the actions; which files exist is known only to Bitwarden.
# Source after lib.sh. Same rules as windows/scripts/store-lib.ps1.
# shellcheck disable=SC2034  # STORE_TEMPLATE, STORE_CHANGED and M_* are read by the scripts that source this file

STORE_ITEM_NAME="Bitwarden-store"
STORE_MANIFEST="_manifest.txt"
STORE_FORMAT="1"
STORE_SYSTEM="linux"
STORE_MAX_BYTES=$((100 * 1024 * 1024)) # Bitwarden's limit per attachment
STORE_TEMPLATE='# Bitwarden-store manifest (see README.md, "Private files")
format: 1

# attachment    | system  | action | action params          | extra'

# State of the open store: the item, its attachments by name, downloads (by attachment id), temp folder.
STORE_TMP="" STORE_ITEM_ID="" STORE_ITEM_JSON=""
declare -gA STORE_ATT_ID=() STORE_ATT_DUP=() STORE_DOWNLOADED=()
n_ok=0 n_updated=0 n_skipped=0 n_errors=0

store_error() { n_errors=$((n_errors + 1)); warn "$*"; }

# Leading/trailing whitespace (and a Windows CR) removed → REPLY.
trim() {
  local s="${1%$'\r'}"
  s="${s#"${s%%[![:space:]]*}"}"
  REPLY="${s%"${s##*[![:space:]]}"}"
}


######
###### SESSION AND TEMP FOLDER
######

# Temp folder for downloads and uploads: ~/.dotfiles/local/tmp/bw-XXXXXXXX (mode 700; /local/ is in .gitignore).
# Leftovers of a run that was killed before its clean-up (e.g. power off) are removed first.
store_start_temp() {
  local root="$DOTFILES_DIR/local/tmp"
  rm -rf "$root"/bw-* 2>/dev/null || true
  mkdir -p "$root"
  STORE_TMP="$(mktemp -d "$root/bw-XXXXXXXX")"
}

# Locks bw and removes the temp folder; for "trap store_stop EXIT".
store_stop() {
  bw_close_session
  [[ -z "$STORE_TMP" ]] || rm -rf "$STORE_TMP"
}

# A fresh subfolder of the temp folder → REPLY (the file name of an upload is its attachment name).
store_tmpdir() { REPLY="$(mktemp -d "$STORE_TMP/XXXXXXXX")"; }


######
###### ITEM AND ATTACHMENTS
######

# Reads the note (by id after a change, else by name). Returns 1 when it does not exist.
store_load_item() {
  if [[ -n "$STORE_ITEM_ID" ]]; then
    STORE_ITEM_JSON="$(bw get item "$STORE_ITEM_ID")" || die "bw get item $STORE_ITEM_NAME failed"
  else
    STORE_ITEM_JSON="$(bw list items --search "$STORE_ITEM_NAME" |
      jq -c --arg name "$STORE_ITEM_NAME" '[.[] | select(.name == $name)][0] // empty')"
    [[ -n "$STORE_ITEM_JSON" ]] || return 1
    STORE_ITEM_ID="$(jq -r .id <<<"$STORE_ITEM_JSON")"
  fi
  # Bitwarden allows two attachments with the same name; such a name cannot be used.
  STORE_ATT_ID=() STORE_ATT_DUP=()
  local name count id
  while IFS=$'\t' read -r name count id; do
    if ((count > 1)); then STORE_ATT_DUP[$name]="$count"; else STORE_ATT_ID[$name]="$id"; fi
  done < <(jq -r '(.attachments // []) | group_by(.fileName)[] | [.[0].fileName, length, .[0].id] | @tsv' <<<"$STORE_ITEM_JSON")
}

# Creates the empty secure note (after asking). Returns 1 when the user says no.
store_create_item() {
  local answer encoded
  read -rp "Bitwarden has no item '$STORE_ITEM_NAME'. Create it (an empty secure note)? (y/N) " answer
  [[ "${answer,,}" == y || "${answer,,}" == yes ]] || return 1
  encoded="$(jq -nc --arg name "$STORE_ITEM_NAME" \
    '{type: 2, name: $name, notes: null, secureNote: {type: 0}, favorite: false}' | base64 -w0)"
  STORE_ITEM_ID="$(bw create item "$encoded" | jq -r .id)" || die "bw create item $STORE_ITEM_NAME failed"
  [[ -n "$STORE_ITEM_ID" && "$STORE_ITEM_ID" != null ]] || die "bw create item $STORE_ITEM_NAME failed"
  ok "created $STORE_ITEM_NAME"
  store_load_item
}

store_is_attachment() { [[ -n "${STORE_ATT_ID[$1]:-}" ]]; }

# Stops when $1 is the name of several attachments.
store_assert_name() {
  [[ -z "${STORE_ATT_DUP[$1]:-}" ]] ||
    die "$STORE_ITEM_NAME has ${STORE_ATT_DUP[$1]} attachments named $1; remove the extra ones in Bitwarden"
}

# Downloads an attachment once (per attachment id) into the temp folder → REPLY (its path).
# 1: no such attachment, 2: download failed, 3: several attachments with this name.
store_get() {
  local name="$1" id path
  [[ -z "${STORE_ATT_DUP[$name]:-}" ]] || return 3
  id="${STORE_ATT_ID[$name]:-}"
  [[ -n "$id" && "$name" != */* ]] || return 1
  if [[ -n "${STORE_DOWNLOADED[$id]:-}" ]]; then
    REPLY="${STORE_DOWNLOADED[$id]}"
    return 0
  fi
  store_tmpdir
  path="$REPLY/$name"
  if ! bw get attachment "$id" --itemid "$STORE_ITEM_ID" --output "$path" >/dev/null 2>&1 || [[ ! -f "$path" ]]; then
    return 2
  fi
  STORE_DOWNLOADED[$id]="$path"
  REPLY="$path"
}

# Uploads file $1 as the attachment $2 (bw names it after the file, so a copy with that name is uploaded). 1: failed.
store_upload() {
  local path="$1" name="$2"
  if (($(stat -c %s "$path") > STORE_MAX_BYTES)); then
    warn "$name is larger than 100 MB (Bitwarden's limit)"
    return 1
  fi
  store_tmpdir
  cp "$path" "$REPLY/$name"
  if ! bw create attachment --file "$REPLY/$name" --itemid "$STORE_ITEM_ID" >/dev/null; then
    warn "bw create attachment $name failed"
    return 1
  fi
  store_load_item
}

store_delete() {
  local name="$1"
  store_assert_name "$name"
  bw delete attachment "${STORE_ATT_ID[$name]}" --itemid "$STORE_ITEM_ID" >/dev/null || die "bw delete attachment $name failed"
  store_load_item
}

# Replaces the attachment $1 with file $2 and keeps the version it replaces as "$1.prev" (one step back).
# $2 empty: removes $1, still keeping "$1.prev". STORE_CHANGED=0 when the content is the same (nothing done).
# Order: delete the old one, then upload the new one (never two attachments with the same name). If the upload
# fails, the old version is "$1.prev" and the new file is still at $2 (stops with that message).
store_set() {
  local name="$1" new="$2" current="" rc=0
  STORE_CHANGED=0
  store_get "$name" || rc=$?
  case $rc in
    0) current="$REPLY" ;;
    1) ;;
    3) store_assert_name "$name" ;;
    *) die "bw get attachment $name failed" ;;
  esac
  if [[ -n "$new" && -n "$current" ]] && cmp -s "$new" "$current"; then return 0; fi
  if [[ -n "$current" ]]; then
    if store_is_attachment "$name.prev"; then store_delete "$name.prev"; fi
    store_upload "$current" "$name.prev" || die "could not keep the previous version of $name; nothing changed"
    store_delete "$name"
  fi
  if [[ -n "$new" ]]; then
    store_upload "$new" "$name" ||
      die "the previous version is $name.prev in $STORE_ITEM_NAME; the new file is still at $new: run the command again"
  fi
  STORE_CHANGED=1
}


######
###### MANIFEST
######

# Parses a manifest file:   attachment | system | action | action params | extra
# Whole-line comments (#) and blank lines are ignored. Sets M_FORMAT, M_PROBLEMS and per entry (all systems)
# M_NUM M_ATT M_SYS M_ACT M_PAR M_HOSTS M_WHEN M_MODE.
manifest_parse() {
  local file="$1" raw line number=0 att sys action param extra hosts when mode option key value bad
  M_FORMAT="" M_PROBLEMS=() M_NUM=() M_ATT=() M_SYS=() M_ACT=() M_PAR=() M_HOSTS=() M_WHEN=() M_MODE=()
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    number=$((number + 1))
    trim "${raw#$'\xef\xbb\xbf'}"
    line="$REPLY"
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" =~ ^format[[:space:]]*:[[:space:]]*([^[:space:]]+)$ ]]; then
      M_FORMAT="${BASH_REMATCH[1]}"
      continue
    fi

    IFS='|' read -r att sys action param extra <<<"$line"
    trim "$att" && att="$REPLY"
    trim "$sys" && sys="${REPLY,,}"
    trim "$action" && action="${REPLY,,}"
    trim "$param" && param="$REPLY"
    trim "$extra" && extra="$REPLY"

    bad=""
    if [[ -z "$att" || -z "$action" ]]; then bad="incomplete line"
    elif [[ "$sys" != windows && "$sys" != linux && "$sys" != all ]]; then bad="unknown system '$sys'"
    elif [[ "$action" != copy && "$action" != font && "$action" != unzip ]]; then bad="unknown action '$action'"
    elif [[ "$action" == copy && -z "$param" ]]; then bad="copy needs a target path"
    elif [[ "$action" == unzip && -z "$param" ]]; then bad="unzip needs a target folder"
    elif [[ "$action" == font && -n "$param" ]]; then bad="font takes no parameters"
    fi

    hosts="" when="always" mode=""
    if [[ -z "$bad" ]]; then
      set -f
      for option in $extra; do
        key="${option%%=*}" value="${option#*=}"
        [[ "$option" == *=* ]] || key=""
        case "${key,,}" in
          host) hosts="${value,,}" ;;
          when) if [[ "$value" == always || "$value" == missing ]]; then when="$value"; else bad="bad option '$option'"; fi ;;
          mode) if [[ "$value" =~ ^[0-7]{3,4}$ ]]; then mode="$value"; else bad="bad option '$option'"; fi ;;
          *) bad="bad option '$option'" ;;
        esac
        [[ -z "$bad" ]] || break
      done
      set +f
    fi
    if [[ -n "$bad" ]]; then
      M_PROBLEMS+=("line $number: $bad ($line)")
      continue
    fi
    M_NUM+=("$number") M_ATT+=("$att") M_SYS+=("$sys") M_ACT+=("$action") M_PAR+=("$param")
    M_HOSTS+=("$hosts") M_WHEN+=("$when") M_MODE+=("$mode")
  done <"$file"
  if [[ "$M_FORMAT" != "$STORE_FORMAT" ]]; then
    M_PROBLEMS=("needs 'format: $STORE_FORMAT' (found: ${M_FORMAT:-none})" "${M_PROBLEMS[@]}")
  fi
}

# The manifest lines of file $1 that name $2 as their attachment (raw text, one per line).
manifest_lines_for() {
  local raw line
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    trim "$raw"
    line="$REPLY"
    [[ -z "$line" || "$line" == \#* ]] && continue
    trim "${line%%|*}"
    [[ "$REPLY" == "$2" ]] && printf '%s\n' "$raw"
  done <"$1"
  return 0
}

# Opens file $1 in the editor until it is a valid manifest. 0: valid; 1: the user cancelled.
# Editor: $EDITOR (e.g. "code --wait"), else nano.
manifest_edit() {
  local file="$1" answer problem editor
  read -ra editor <<<"${EDITOR:-nano}"
  while true; do
    "${editor[@]}" "$file" </dev/tty >/dev/tty
    manifest_parse "$file"
    ((${#M_PROBLEMS[@]})) || return 0
    warn "$STORE_MANIFEST has problems:"
    for problem in "${M_PROBLEMS[@]}"; do printf '    %s\n' "$problem"; done
    read -rp 'Edit again? (Y/n; n cancels, nothing is saved) ' answer
    [[ "${answer,,}" != n && "${answer,,}" != no ]] || return 1
  done
}


######
###### ACTIONS (restore)
######

# ~ at the start means $HOME; $VAR and ${VAR} are expanded (no eval) → REPLY.
expand_path() {
  local p="$1" out="" match name re='\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?'
  # shellcheck disable=SC2088  # a literal ~ in the manifest
  [[ "$p" == "~" || "$p" == "~/"* ]] && p="$HOME${p:1}"
  while [[ "$p" =~ $re ]]; do
    match="${BASH_REMATCH[0]}" name="${BASH_REMATCH[1]}"
    out+="${p%%"$match"*}${!name:-}"
    p="${p#*"$match"}"
  done
  REPLY="$out$p"
}

# copy <path>: the attachment goes to <path>, overwritten when different (when=missing: only when there is none).
action_copy() {
  local att="$1" src="$2" param="$3" when="$4" mode="$5" target
  expand_path "$param"
  target="$REPLY"
  [[ "$target" == /* ]] || { store_error "copy: not an absolute path: $param"; return 0; }
  if [[ -e "$target" ]] && { [[ "$when" == missing ]] || cmp -s "$src" "$target"; }; then
    [[ -z "$mode" ]] || chmod "$mode" "$target"
    n_ok=$((n_ok + 1))
    ok "$target up to date"
    return 0
  fi
  mkdir -p "$(dirname "$target")" 2>/dev/null || { store_error "copy: cannot create $(dirname "$target") (no access?)"; return 0; }
  if [[ -n "$mode" ]]; then
    install -m "$mode" "$src" "$target" 2>/dev/null || { store_error "copy: cannot write $target (no access?)"; return 0; }
  else
    cp "$src" "$target" 2>/dev/null || { store_error "copy: cannot write $target (no access?)"; return 0; }
  fi
  n_updated=$((n_updated + 1))
  ok "$target updated from $att"
}

# font: the .ttf/.otf attachment is installed for the current user (~/.local/share/fonts).
action_font() {
  local att="$1" src="$2" dir="$HOME/.local/share/fonts"
  [[ "$att" =~ \.(ttf|otf)$ ]] || { store_error "font: not a .ttf/.otf file: $att"; return 0; }
  if cmp -s "$src" "$dir/$att"; then
    n_ok=$((n_ok + 1))
    ok "font $att installed"
    return 0
  fi
  mkdir -p "$dir"
  cp "$src" "$dir/$att"
  if command_exists fc-cache; then fc-cache -f "$dir" >/dev/null 2>&1 || true; fi
  n_updated=$((n_updated + 1))
  ok "font $att installed"
}


# unzip <folder>: the .zip attachment is unpacked into <folder>; files that differ are overwritten, the others and files
# that are not in the zip are left alone. when=missing: only when the folder does not exist yet.
action_unzip() {
  local att="$1" src="$2" param="$3" when="$4" target dir file rel n=0
  [[ "$att" == *.zip ]] || { store_error "unzip: not a .zip file: $att"; return 0; }
  expand_path "$param"
  target="$REPLY"
  [[ "$target" == /* ]] || { store_error "unzip: not an absolute path: $param"; return 0; }
  if [[ -e "$target" && "$when" == missing ]]; then
    n_ok=$((n_ok + 1))
    ok "$target up to date"
    return 0
  fi
  command_exists unzip || { store_error "unzip: the unzip command is not installed (apt step)"; return 0; }
  # Every entry must stay inside the folder (no absolute paths, no ..).
  if ! unzip -Z1 "$src" >/dev/null 2>&1 || unzip -Z1 "$src" | grep -qE '(^/|(^|/)\.\.(/|$))'; then
    store_error "unzip: $att is not a valid zip or has paths outside its folder"
    return 0
  fi
  store_tmpdir
  dir="$REPLY"
  unzip -q "$src" -d "$dir" || { store_error "unzip: $att could not be unpacked"; return 0; }
  while IFS= read -r -d '' file; do
    rel="${file#"$dir"/}"
    cmp -s "$file" "$target/$rel" && continue
    if ! mkdir -p "$(dirname "$target/$rel")" 2>/dev/null || ! cp "$file" "$target/$rel" 2>/dev/null; then
      store_error "unzip: cannot write $target/$rel (no access, or $target is a broken link?)"
      return 0
    fi
    n=$((n + 1))
  done < <(find "$dir" -type f -print0)
  if ((n)); then
    n_updated=$((n_updated + 1))
    ok "$target updated from $att ($n file(s))"
  else
    n_ok=$((n_ok + 1))
    ok "$target up to date"
  fi
}


######
###### RESTORE
######

# Applies the manifest for this system and computer (the session and the item must be open). Prints a summary.
store_restore() {
  local i rc host problem manifest
  n_ok=0 n_updated=0 n_skipped=0 n_errors=0
  rc=0
  store_get "$STORE_MANIFEST" || rc=$?
  if ((rc != 0)); then
    warn "$STORE_ITEM_NAME has no usable attachment $STORE_MANIFEST; nothing done (create it: dlab-store-manifest-edit)"
    return 0
  fi
  manifest="$REPLY"
  manifest_parse "$manifest"
  if [[ "$M_FORMAT" != "$STORE_FORMAT" ]]; then
    store_error "manifest: needs 'format: $STORE_FORMAT' (found: ${M_FORMAT:-none}); nothing done"
  else
    for problem in "${M_PROBLEMS[@]}"; do store_error "manifest: $problem"; done
    host="$(hostname)"
    for i in "${!M_ATT[@]}"; do
      if [[ "${M_SYS[i]}" != "$STORE_SYSTEM" && "${M_SYS[i]}" != all ]]; then n_skipped=$((n_skipped + 1)); continue; fi
      if [[ -n "${M_HOSTS[i]}" && ",${M_HOSTS[i]}," != *",${host,,},"* ]]; then n_skipped=$((n_skipped + 1)); continue; fi
      rc=0
      store_get "${M_ATT[i]}" || rc=$?
      case $rc in
        1) store_error "$STORE_ITEM_NAME has no attachment ${M_ATT[i]} (manifest line ${M_NUM[i]})"; continue ;;
        2) store_error "bw get attachment ${M_ATT[i]} failed"; continue ;;
        3) store_error "$STORE_ITEM_NAME has ${STORE_ATT_DUP[${M_ATT[i]}]} attachments named ${M_ATT[i]}; remove the extra ones in Bitwarden"; continue ;;
      esac
      case "${M_ACT[i]}" in
        copy) action_copy "${M_ATT[i]}" "$REPLY" "${M_PAR[i]}" "${M_WHEN[i]}" "${M_MODE[i]}" ;;
        font) action_font "${M_ATT[i]}" "$REPLY" ;;
        unzip) action_unzip "${M_ATT[i]}" "$REPLY" "${M_PAR[i]}" "${M_WHEN[i]}" ;;
      esac
    done
  fi
  local summary="$STORE_ITEM_NAME: $n_ok ok, $n_updated updated, $n_skipped skipped (other system or computer), $n_errors errors"
  if ((n_errors)); then warn "$summary"; else ok "$summary"; fi
}

# The git name and e-mail are not in the repo (see git/.gitconfig): without the store, commits fail.
check_git_identity() {
  if command_exists git && [[ -z "$(git config --get user.email || true)" ]]; then
    warn "git has no user.email: it comes from $STORE_ITEM_NAME (~/.dotfiles/local/.gitconfig.user); commits fail until then"
  fi
}
