#!/usr/bin/env bash
# Optional features on top of install.sh: pick them from a checklist, install them, keep them updated.
#
#   ~/.dotfiles/ubuntu/features.sh              # checklist (whiptail, or one yes/no question per feature)
#   ~/.dotfiles/ubuntu/features.sh uv node      # install these without asking and remember them
#   ~/.dotfiles/ubuntu/features.sh --update     # install/update the remembered features (install.sh runs this)
#   ~/.dotfiles/ubuntu/features.sh --list       # show every feature and its state
#
# The selection is stored per machine in ~/.config/dotfiles/features (not in the repo).
# Unticking a feature only stops updating it; nothing is uninstalled.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/scripts/lib.sh"

FEATURES_DIR="$UBUNTU_DIR/features"
SELECTION_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/features"

[[ $EUID -ne 0 ]] || die "run as your normal user, not root (sudo is used where needed)"

mapfile -t feature_files < <(find "$FEATURES_DIR" -maxdepth 1 -name '[0-9][0-9]-*.sh' | sort)
(( ${#feature_files[@]} > 0 )) || die "no features found in $FEATURES_DIR"

feature_name() {
  local base
  base="$(basename "$1" .sh)"
  echo "${base#[0-9][0-9]-}"
}

# Line 2 of a feature script is its one-line description.
feature_label() { sed -n '2s/^# *//p' "$1"; }

feature_file() {
  local file
  for file in "${feature_files[@]}"; do
    if [[ "$(feature_name "$file")" == "$1" ]]; then
      echo "$file"
      return 0
    fi
  done
  return 1
}

all_names() {
  local file
  for file in "${feature_files[@]}"; do feature_name "$file"; done
}

# Sets STATE (short text) and STATE_RC: 0 installed, 1 not installed, 2 not available on this machine.
read_state() {
  STATE="$(bash "$1" status 2>&1)" && STATE_RC=0 || STATE_RC=$?
}

remembered() {
  [[ -r "$SELECTION_FILE" ]] || return 0
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$SELECTION_FILE" | grep -v '^$' || true
}

is_remembered() { remembered | grep -qx "$1"; }

save_selection() {
  mkdir -p "$(dirname "$SELECTION_FILE")"
  if (( $# > 0 )); then
    printf '%s\n' "$@" > "$SELECTION_FILE"
  else
    : > "$SELECTION_FILE"
  fi
  ok "remembered features: ${*:-none} ($SELECTION_FILE)"
}

# Prints the given names that can be installed here; warns about the others.
available_only() {
  local name
  for name in "$@"; do
    read_state "$(feature_file "$name")"
    if (( STATE_RC == 2 )); then
      warn "$name: not available on this machine ($STATE), not remembered"
    else
      echo "$name"
    fi
  done
}

list_features() {
  local file name mark
  for file in "${feature_files[@]}"; do
    name="$(feature_name "$file")"
    read_state "$file"
    mark=""
    if is_remembered "$name"; then mark=", remembered"; fi
    printf '  %-12s %-28s %s\n' "$name" "$STATE$mark" "$(feature_label "$file")"
  done
}

install_features() {
  local name file failed=()
  if (( $# == 0 )); then
    ok "no features to install"
    return 0
  fi
  for name in "$@"; do
    if ! file="$(feature_file "$name")"; then
      warn "unknown feature: $name"
      failed+=("$name")
      continue
    fi
    read_state "$file"
    if (( STATE_RC == 2 )); then
      warn "$name: not available on this machine ($STATE), skipped"
      continue
    fi
    log "feature $name"
    if ! bash "$file" install; then
      warn "feature $name failed"
      failed+=("$name")
    fi
  done
  (( ${#failed[@]} == 0 )) || die "failed features: ${failed[*]}"
  ok "features done: $*"
}

# Checklist (whiptail) or one question per feature. Prints the chosen names, one per line.
# Pre-selected: installed features and remembered ones that are not installed yet.
choose_features() {
  local file name on answer i items=() names=() defaults=()
  for file in "${feature_files[@]}"; do
    name="$(feature_name "$file")"
    read_state "$file"
    on=OFF
    if (( STATE_RC == 0 )) || { (( STATE_RC == 1 )) && is_remembered "$name"; }; then on=ON; fi
    names+=("$name")
    defaults+=("$on")
    items+=("$name" "$(feature_label "$file") [$STATE]" "$on")
  done

  if command_exists whiptail && [[ -t 0 && -t 2 ]]; then
    local out
    out="$(whiptail --title "dotfiles: optional features" --separate-output \
      --checklist "Space: select   Enter: install   Esc: cancel" 18 100 "${#names[@]}" "${items[@]}" \
      3>&1 1>&2 2>&3)" || die "cancelled, nothing changed"
    printf '%s\n' "$out" | grep -v '^$' || true
    return 0
  fi

  [[ -t 0 ]] || die "no terminal: pass feature names or --update"
  warn "whiptail not found, asking one by one"
  for ((i = 0; i < ${#names[@]}; i++)); do
    if [[ "${defaults[i]}" == ON ]]; then
      read -r -p "  ${names[i]}: ${items[i * 3 + 1]} [Y/n] " answer
      [[ "${answer,,}" == n* ]] || echo "${names[i]}"
    else
      read -r -p "  ${names[i]}: ${items[i * 3 + 1]} [y/N] " answer
      [[ "${answer,,}" != y* ]] || echo "${names[i]}"
    fi
  done
  return 0
}

names=()
case "${1:-}" in
  --list)
    list_features
    ;;
  --update)
    mapfile -t names < <(remembered)
    install_features "${names[@]}"
    ;;
  -h | --help)
    sed -n '3,10s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
    ;;
  -*)
    die "unknown option: $1 (see --help)"
    ;;
  "")
    chosen="$(choose_features)"
    mapfile -t names < <(printf '%s\n' "$chosen" | grep -v '^$' || true)
    mapfile -t names < <(available_only "${names[@]}")
    save_selection "${names[@]}"
    install_features "${names[@]}"
    ;;
  *)
    for name in "$@"; do
      feature_file "$name" >/dev/null || die "unknown feature: $name (available: $(all_names | xargs))"
    done
    mapfile -t wanted < <(available_only "$@")
    mapfile -t names < <({ remembered; printf '%s\n' "${wanted[@]}"; } | grep -v '^$' | awk '!seen[$0]++')
    save_selection "${names[@]}"
    install_features "${wanted[@]}"
    ;;
esac
