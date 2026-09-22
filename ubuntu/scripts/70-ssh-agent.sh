#!/usr/bin/env bash
# WSL: SSH keys from the Bitwarden desktop agent on Windows (socat + npiperelay bridge).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Native Ubuntu (server): keys come from the forwarded agent, nothing to set up.
is_wsl || exit 0

AGENT_SOCK="$HOME/.ssh/bitwarden-agent.sock"

if ! command_exists socat; then
  log "installing socat (relays the Unix socket to the Windows named pipe)"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y socat
  hash -r
fi

# Installed on Windows with: winget install --id albertony.npiperelay -e
# WSL finds it by name because winget puts a link in %LOCALAPPDATA%\Microsoft\WinGet\Links,
# which is on the Windows PATH that WSL appends.
if ! command_exists npiperelay.exe; then
  warn "npiperelay.exe not found; the Bitwarden agent will not be available in WSL"
  cat <<'MSG'
     On Windows, once per computer:
       1. winget install --id albertony.npiperelay -e
       2. Bitwarden Desktop -> Settings -> enable the SSH agent
       3. Services -> OpenSSH Authentication Agent -> Startup type: Disabled
          (it claims the same named pipe as Bitwarden)
MSG
  exit 0
fi

ok "npiperelay.exe $(npiperelay.exe -h 2>&1 | head -n1)"

# The relay itself is started by ~/.config/zsh/wsl.zsh in every new shell; here we only report
# whether the Windows side actually answers, so a broken setup is visible during install.
if [[ -S "$AGENT_SOCK" ]] && keys="$(SSH_AUTH_SOCK="$AGENT_SOCK" ssh-add -l 2>/dev/null)"; then
  ok "Bitwarden agent answers: $(wc -l <<<"$keys") key(s)"
else
  ok "bridge configured; it starts with your next shell"
  warn "if 'ssh-add -l' stays empty: unlock Bitwarden and check its SSH agent setting"
fi
