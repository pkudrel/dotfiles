# dlab-{area}-{action} commands for this dotfiles setup. List them with dlab-help (or dlab-<Tab>).

typeset -g DLAB_DOTFILES_DIR="${DLAB_DOTFILES_DIR:-$HOME/.dotfiles}"
typeset -gA DLAB_COMMANDS

DLAB_COMMANDS[dlab-dotfiles-update]="get the latest dotfiles (git pull), apply them (install.sh), start a new shell"
dlab-dotfiles-update() {
  # --ff-only: a rewritten GitHub history (or local commits) stops here instead of being merged.
  git -C "$DLAB_DOTFILES_DIR" pull --ff-only || {
    print -u2 "dlab: git pull failed (history differs from GitHub?), nothing applied (see dlab-dotfiles-status)"
    return 1
  }
  "$DLAB_DOTFILES_DIR/ubuntu/install.sh" || {
    print -u2 "dlab: install.sh failed, shell not restarted"
    return 1
  }
  exec zsh
}

# Version of a git ref from the v* tags created by GitHub Actions: "0.1.8", "0.1.8 +2 commits", or nothing.
_dlab_version() {
  setopt local_options extended_glob
  local described
  described="$(git -C "$DLAB_DOTFILES_DIR" describe --tags --match 'v[0-9]*' "$1" 2>/dev/null)" || return 0
  if [[ "$described" == (#b)v(*)-([0-9]##)-g[0-9a-f]## ]]; then
    print -r -- "$match[1] +$match[2] commit${${match[2]:#1}:+s}"
  else
    print -r -- "${described#v}"
  fi
}

DLAB_COMMANDS[dlab-dotfiles-status]="compare with GitHub: versions, local changes, commits to pull / not pushed yet (fetches first)"
dlab-dotfiles-status() {
  local incoming outgoing here latest
  git -C "$DLAB_DOTFILES_DIR" fetch --quiet --tags || print -u2 "dlab: fetch failed, showing the last known GitHub state"
  git -C "$DLAB_DOTFILES_DIR" status -sb

  here="$(_dlab_version HEAD)"
  latest="$(git -C "$DLAB_DOTFILES_DIR" describe --tags --abbrev=0 --match 'v[0-9]*' '@{u}' 2>/dev/null)"
  print "\nThis machine: ${here:-no version tag yet}"
  if [[ -z "$latest" ]]; then
    print "GitHub:       no version tag yet (GitHub Actions creates them after a push to main)"
  elif git -C "$DLAB_DOTFILES_DIR" merge-base --is-ancestor "$latest" HEAD 2>/dev/null; then
    print "GitHub:       ${latest#v}"
  else
    print "GitHub:       ${latest#v}  → update available: dlab-dotfiles-update"
  fi

  incoming="$(git -C "$DLAB_DOTFILES_DIR" log --oneline 'HEAD..@{u}' 2>/dev/null)"
  outgoing="$(git -C "$DLAB_DOTFILES_DIR" log --oneline '@{u}..HEAD' 2>/dev/null)"
  if [[ -n "$incoming" ]]; then
    print "\nTo pull (dlab-dotfiles-update):"
    print -r -- "$incoming"
  fi
  if [[ -n "$outgoing" ]]; then
    print "\nNot pushed yet:"
    print -r -- "$outgoing"
  fi
  return 0
}

DLAB_COMMANDS[dlab-dotfiles-version]="version of this machine's dotfiles (local, no network; compare with GitHub: dlab-dotfiles-status)"
dlab-dotfiles-version() {
  local version
  version="$(_dlab_version HEAD)"
  if [[ -z "$version" ]]; then
    print -u2 "dlab: no version tag in this checkout yet (dlab-dotfiles-status fetches tags from GitHub)"
    return 1
  fi
  print -r -- "$version"
}

DLAB_COMMANDS[dlab-dotfiles-cd]="go to the dotfiles repo"
dlab-dotfiles-cd() {
  cd "$DLAB_DOTFILES_DIR"
}

DLAB_COMMANDS[dlab-dotfiles-edit]="open the dotfiles repo in VS Code"
dlab-dotfiles-edit() {
  if (( $+commands[code] )); then
    code "$DLAB_DOTFILES_DIR"
  else
    print -u2 "dlab: VS Code ('code') not found, going to the repo instead"
    cd "$DLAB_DOTFILES_DIR"
  fi
}

DLAB_COMMANDS[dlab-dotfiles-stow]="re-link config files into ~ (install.sh stow), e.g. after new zsh modules"
dlab-dotfiles-stow() {
  "$DLAB_DOTFILES_DIR/ubuntu/install.sh" stow
}

DLAB_COMMANDS[dlab-store-restore]="put the files from Bitwarden-store in place (install.sh bitwarden-store; asks for the master password)"
dlab-store-restore() {
  "$DLAB_DOTFILES_DIR/ubuntu/install.sh" bitwarden-store
}

DLAB_COMMANDS[dlab-store-list]="what is in Bitwarden-store: attachments and the manifest lines that use them"
dlab-store-list() { "$DLAB_DOTFILES_DIR/ubuntu/store.sh" list }

DLAB_COMMANDS[dlab-store-add]="add a file to Bitwarden-store (dlab-store-add <file>; its manifest line is written in the editor)"
dlab-store-add() { "$DLAB_DOTFILES_DIR/ubuntu/store.sh" add "$@" }

DLAB_COMMANDS[dlab-store-replace]="new version of a file in Bitwarden-store (dlab-store-replace <file>; the old one stays as <name>.prev)"
dlab-store-replace() { "$DLAB_DOTFILES_DIR/ubuntu/store.sh" replace "$@" }

DLAB_COMMANDS[dlab-store-remove]="remove a file and its manifest lines from Bitwarden-store (dlab-store-remove <name>; asks first)"
dlab-store-remove() { "$DLAB_DOTFILES_DIR/ubuntu/store.sh" remove "$@" }

DLAB_COMMANDS[dlab-store-manifest-edit]="edit _manifest.txt of Bitwarden-store (checked before it is saved)"
dlab-store-manifest-edit() { "$DLAB_DOTFILES_DIR/ubuntu/store.sh" manifest-edit }

DLAB_COMMANDS[dlab-features-select]="pick optional features from a checklist (or pass names: dlab-features-select uv node)"
dlab-features-select() {
  "$DLAB_DOTFILES_DIR/ubuntu/features.sh" "$@"
}

DLAB_COMMANDS[dlab-features-list]="state of every optional feature"
dlab-features-list() {
  "$DLAB_DOTFILES_DIR/ubuntu/features.sh" --list
}

DLAB_COMMANDS[dlab-features-update]="install/update the remembered optional features"
dlab-features-update() {
  "$DLAB_DOTFILES_DIR/ubuntu/features.sh" --update
}

DLAB_COMMANDS[dlab-help]="this list"
dlab-help() {
  local name
  for name in ${(ko)DLAB_COMMANDS}; do
    printf '  %-22s %s\n' "$name" "$DLAB_COMMANDS[$name]"
  done
}
