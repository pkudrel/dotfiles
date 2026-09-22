#!/usr/bin/env bash
# Shared helpers for the install steps. Source it, don't run it.

UBUNTU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DOTFILES_DIR="$(dirname "$UBUNTU_DIR")"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)}"
LOCAL_BIN="$HOME/.local/bin"
export PATH="$LOCAL_BIN:$PATH"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERR\033[0m %s\n' "$*" >&2; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

is_wsl() { [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; }

# version_ge A B: true when version A >= B.
version_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]; }

# Candidate version of an apt package ("" when unavailable), without epoch and Debian suffix.
apt_candidate() {
  local v
  v="$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}')"
  [[ "$v" =~ ^([0-9]+:)?[0-9] ]] || return 0
  v="${v#*:}"
  echo "${v%%[-+~]*}"
}

# Latest release tag of a GitHub repo (e.g. v0.56.0), resolved from the redirect.
github_latest_tag() {
  curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's#.*/tag/##'
}

# Download a .tar.gz and install the binary named $2 from it into ~/.local/bin.
install_from_tarball() {
  local url="$1" bin="$2" tmp found
  tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/pkg.tar.gz" || { rm -rf "$tmp"; die "download failed: $url"; }
  tar -xzf "$tmp/pkg.tar.gz" -C "$tmp"
  found="$(find "$tmp" -type f -name "$bin" | head -n1)"
  [[ -n "$found" ]] || { rm -rf "$tmp"; die "$bin not found in $url"; }
  mkdir -p "$LOCAL_BIN"
  install -m 0755 "$found" "$LOCAL_BIN/$bin"
  rm -rf "$tmp"
  ok "installed $bin → $LOCAL_BIN/$bin"
}

# Move $1 out of the way (into $BACKUP_DIR) unless it is missing or already links into this repo.
backup_file() {
  local target="$1" rel
  if [[ -L "$target" ]]; then
    [[ "$(readlink -f "$target")" == "$DOTFILES_DIR"/* ]] && return 0
  elif [[ ! -e "$target" ]]; then
    return 0
  fi
  rel="${target#"$HOME"/}"
  mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
  mv "$target" "$BACKUP_DIR/$rel"
  warn "backed up $target → $BACKUP_DIR/$rel"
}

# Copy $1 to $2 only when $2 does not exist yet; never overwrite.
copy_if_missing() {
  local src="$1" dst="$2"
  if [[ -e "$dst" || -L "$dst" ]]; then
    ok "exists, left untouched: $dst"
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    ok "created $dst"
  fi
}

# True when the apt package $1 is installed.
pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }

# Newest apt package whose whole name matches the regex $1 (e.g. 'libicu[0-9]+'); "" when none.
apt_newest_matching() { apt-cache pkgnames 2>/dev/null | grep -E "^($1)\$" | sort -V | tail -n1 || true; }

# True when systemd runs as PID 1 (docker and tailscaled need it; WSL can run without it).
has_systemd() { [[ "$(ps -p 1 -o comm= 2>/dev/null)" == systemd ]]; }

# Ubuntu release codename, e.g. "resolute" for 26.04.
os_codename() (
  # shellcheck source=/dev/null
  . /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
)

# Bitwarden CLI (bw) in ~/.local/bin from the official Linux build (x86_64), when missing.
bw_install() {
  command_exists bw && return 0
  command_exists unzip || die "unzip is not installed (run the apt step first)"
  local tmp
  tmp="$(mktemp -d)"
  log "installing the Bitwarden CLI (bw)"
  curl -fsSL "https://vault.bitwarden.com/download/?app=cli&platform=linux" -o "$tmp/bw.zip" ||
    { rm -rf "$tmp"; die "bw download failed"; }
  unzip -q -o "$tmp/bw.zip" -d "$tmp"
  mkdir -p "$LOCAL_BIN"
  install -m 0755 "$tmp/bw" "$LOCAL_BIN/bw"
  rm -rf "$tmp"
  ok "installed bw → $LOCAL_BIN/bw"
}

# Unlock the Bitwarden CLI for this process (BW_SESSION); installs bw and logs in first when needed.
# Returns 1 when the master password prompt was left empty (Enter): the caller skips its Bitwarden work.
# The password is asked first, so skipping installs and logs in nothing. It goes through an environment
# variable, never a command line. Close with bw_close_session.
bw_open_session() {
  [[ -t 0 ]] || die "the Bitwarden CLI needs a terminal to ask for the master password"
  command_exists jq || die "jq is not installed (run the apt step first)"
  local password session
  read -rsp 'Bitwarden master password (unlocks the CLI; Enter = skip): ' password
  echo
  [[ -n "$password" ]] || return 1

  bw_install
  export BW_PASSWORD="$password"
  password=""
  if [[ "$(bw status | jq -r .status)" == unauthenticated ]]; then
    # EU vault: run "bw config server https://vault.bitwarden.eu" once before this.
    log "Bitwarden CLI: log in (e-mail and 2FA; the master password is the one given above)"
    bw login --passwordenv BW_PASSWORD >/dev/null || { unset BW_PASSWORD; die "bw login failed"; }
  fi
  session="$(bw unlock --passwordenv BW_PASSWORD --raw)" || session=""
  unset BW_PASSWORD
  [[ -n "$session" ]] || die "bw unlock failed"
  export BW_SESSION="$session"
  bw sync >/dev/null
}

bw_close_session() {
  [[ -n "${BW_SESSION:-}" ]] && bw lock >/dev/null 2>&1
  unset BW_SESSION
  return 0
}
